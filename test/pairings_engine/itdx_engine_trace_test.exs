defmodule PairingsEngine.ItdxEngineTraceTest do
  @moduledoc """
  The engine's trace: kept on the round when it is paired
  (`PairingsEngine.EngineTrace`), written at the bottom of the ITDX file
  (`PairingsEngine.ItdxTrace`), the stored account in its place where there
  is none, and nowhere near the file sent for rating or its copy.
  """
  use PairingsEngine.DataCase, async: false

  import Ecto.Query
  import PairingsEngine.TeamFixtures, only: [team_swiss: 2, pair_next!: 1]

  alias PairingsEngine.{Pairing, Repo, TrfExport, TrfImport, Tournaments}
  alias PairingsEngine.Accounts.{Scope, User}
  alias PairingsEngine.Tournaments.{Round, Tournament}

  @names ~w(Alice Bob Carol Dave Erin Frank Gina)

  # Off for the rest of the suite (config/test.exs); on here.
  setup do
    previous = Application.get_env(:pairings_engine, :engine_trace)
    Application.put_env(:pairings_engine, :engine_trace, true)
    on_exit(fn -> Application.put_env(:pairings_engine, :engine_trace, previous) end)
  end

  defp tournament(attrs \\ []) do
    t =
      Repo.insert!(
        struct(
          Tournament,
          Map.merge(
            %{
              name: "Club championship",
              type: "swiss",
              rounds_count: 3,
              tiebreaks: ~w(BH SB),
              round_dates: ["2026-09-01", "2026-09-08", "2026-09-15"]
            },
            Map.new(attrs)
          )
        )
      )

    for {name, i} <- Enum.with_index(@names) do
      {:ok, _} =
        Tournaments.create_player(t.id, %{
          tournament_id: t.id,
          name: name,
          fide_rating: 2100 - 50 * i,
          fide_id: 20_000_000 + i
        })
    end

    t
  end

  defp pair!(t) do
    {:ok, round} = Pairing.pair_next_round(Repo.reload!(t))
    Tournaments.get_round(t.id, round.number)
  end

  defp play!(round) do
    for p <- round.pairings, p.black_player_id do
      {:ok, _} = Tournaments.update_pairing_result(p, "1-0")
    end
  end

  defp trace(t, number) do
    Repo.one(
      from r in Round,
        where: r.tournament_id == ^t.id and r.number == ^number,
        select: r.engine_trace
    )
  end

  defp itdx(t) do
    {:ok, text} = TrfExport.export(Repo.reload!(t), nil, itdx: true)
    text
  end

  defp lines(text), do: String.split(text, "\r\n")
  defp trace_lines(text), do: Enum.filter(lines(text), &String.starts_with?(&1, "### OP trace"))

  defp user_scope do
    user =
      Repo.insert!(%User{
        email: "user#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    Scope.for_user(user)
  end

  test "pairing a Swiss round keeps the engine's trace on the round, not in a plain load" do
    t = tournament()
    round = pair!(t)

    assert %{"kind" => "individual", "sections" => [section]} = trace(t, 1)
    assert section["matches"] == true
    assert section["text"] =~ "pairing round 1"
    assert section["text"] =~ "Float cascade"
    assert section["text"] =~ "pairing-allocated bye"
    refute section["text"] =~ "Alice"

    # Not loaded unless asked for by name.
    assert %Round{engine_trace: nil} = round
    assert %Round{engine_trace: nil} = Repo.get!(Round, round.id)
  end

  test "the ITDX file ends with the trace of each round, ASCII, no names" do
    t = tournament()
    t |> pair!() |> play!()
    pair!(t)

    text = itdx(t)
    all = lines(text)
    traced = trace_lines(text)

    assert "### OP trace: how Ainalrami paired each round" <> _ = hd(traced)

    assert Enum.any?(
             traced,
             &(&1 =~
                 ~r/^### OP trace R1: engine trace, re-derived .* ends with the stored boards$/)
           )

    assert Enum.any?(traced, &(&1 =~ ~r/^### OP trace R2 \| /))
    assert Enum.any?(traced, &(&1 =~ "### OP trace R2 | Float cascade"))

    # At the bottom: nothing but trace lines after the first of them.
    first = Enum.find_index(all, &String.starts_with?(&1, "### OP trace"))

    assert all
           |> Enum.drop(first)
           |> Enum.reject(&(&1 == ""))
           |> Enum.all?(&String.starts_with?(&1, "### OP trace"))

    assert Enum.find_index(all, &String.starts_with?(&1, "001")) < first

    for line <- traced, do: assert(line =~ ~r/^[\x20-\x7e]+$/)
    refute Enum.any?(traced, &(&1 =~ ~r/Alice|Bob|Carol|Player/))
  end

  test "a round with an account but no trace gets the account, labelled as such" do
    t = tournament()
    pair!(t)
    Repo.update_all(from(r in Round, where: r.tournament_id == ^t.id), set: [engine_trace: nil])

    traced = trace_lines(itdx(t))

    assert "### OP trace R1: stored account (no engine trace was kept for this round)" in traced
    assert Enum.any?(traced, &(&1 =~ ~r/^### OP trace R1 \| bracket 1 score 0\.0: /))
    assert Enum.any?(traced, &(&1 =~ ~r/^### OP trace R1 \| bye: player \d+/))
  end

  test "a pending or missing account says none is stored" do
    t = tournament()
    pair!(t)

    Repo.update_all(from(r in Round, where: r.tournament_id == ^t.id),
      set: [engine_trace: nil, explanation: %{"status" => "pending", "sections" => []}]
    )

    assert "### OP trace R1: none stored - the engine's account was still being worked out" in trace_lines(
             itdx(t)
           )
  end

  test "a round made by hand says there was no engine run to show" do
    t = tournament()
    {:ok, _round} = Pairing.create_round_by_hand(Repo.reload!(t))

    assert Enum.any?(
             trace_lines(itdx(t)),
             &(&1 =~ ~r/^### OP trace R1: none stored - the round was made by hand/)
           )
  end

  test "boards edited after pairing are pointed out" do
    t = tournament()
    round = pair!(t)
    [a, b | _] = Enum.filter(round.pairings, & &1.black_player_id)

    Repo.update_all(from(p in PairingsEngine.Tournaments.Pairing, where: p.id == ^a.id),
      set: [black_player_id: b.black_player_id]
    )

    Repo.update_all(from(p in PairingsEngine.Tournaments.Pairing, where: p.id == ^b.id),
      set: [black_player_id: a.black_player_id]
    )

    assert Enum.any?(
             trace_lines(itdx(t)),
             &(&1 =~ ~r/^### OP trace R1: the boards were edited after the engine paired/)
           )
  end

  test "the file sent for rating and its copy carry none of it" do
    t = tournament()
    t |> pair!() |> play!()

    {:ok, sent} = TrfExport.export(Repo.reload!(t), [1], for: :rating)
    {:ok, copy} = TrfExport.export(Repo.reload!(t), [1], copy: true)
    {:ok, engine} = TrfExport.export(Repo.reload!(t), [1], dialect: :engine)

    refute sent =~ "OP trace"
    refute copy =~ "OP trace"
    refute engine =~ "OP trace"
    assert itdx(t) =~ "### OP trace R1"
  end

  test "an ITDX file with the trace is read back to the same pairings" do
    t = tournament()
    t |> pair!() |> play!()
    pair!(t)
    text = itdx(t)
    assert text =~ "### OP trace R2 | "

    assert {:ok, imported, _warnings} = TrfImport.import_text(text, user_scope())

    boards = fn tournament, n ->
      ranks = tournament.id |> Tournaments.list_players() |> Map.new(&{&1.id, &1.pairing_number})

      for p <- Tournaments.get_round(tournament.id, n).pairings,
          do: {ranks[p.white_player_id], ranks[p.black_player_id]}
    end

    for n <- [1, 2], do: assert(Enum.sort(boards.(imported, n)) == Enum.sort(boards.(t, n)))

    # An imported round was not paired by the engine here.
    assert trace(imported, 1) == nil
  end

  test "the organiser's wishes, exclusions and bye preferences reach the traced run" do
    t = tournament()
    players = t.id |> Tournaments.list_players() |> Enum.sort_by(& &1.fide_rating, :desc)
    [p1, p2, _p3, _p4, _p5, p6, p7] = players

    {:ok, _} = Tournaments.add_forbidden_pairing(Repo.reload!(t), p1.id, p2.id, soft: true)
    {:ok, _} = Tournaments.update_player(p7, %{no_bye: true})
    {:ok, _} = Tournaments.update_player(p6, %{bye_preference: "avoid_soft"})

    pair!(t)

    assert %{"sections" => [section]} = trace(t, 1)
    assert section["matches"] == true
    assert section["text"] =~ "soft pair (XXO)"
    assert section["text"] =~ "bye exclusion (XXO)"
    assert section["text"] =~ "bye preference (XXO)"
  end

  test "a tournament paired by category has one trace per category, each ending with its boards" do
    t =
      Repo.insert!(%Tournament{
        name: "Sections",
        type: "swiss",
        rounds_count: 3,
        tiebreaks: ~w(BH),
        round_dates: List.duplicate("2026-09-01", 3),
        pair_by_category: true,
        categories_enabled: true,
        categories: ["A", "B"]
      })

    for n <- 1..10 do
      {:ok, _} =
        Tournaments.create_player(t.id, %{
          "name" => "P#{n}",
          "fide_rating" => 2100 - n,
          "category" => if(rem(n, 2) == 1, do: "A", else: "B")
        })
    end

    t |> pair!() |> play!()
    pair!(t)

    for n <- [1, 2] do
      assert %{"sections" => [%{"category" => "A"} = a, %{"category" => "B"} = b]} = trace(t, n)
      assert a["matches"] and b["matches"]
    end

    traced = trace_lines(itdx(t))
    assert Enum.any?(traced, &(&1 =~ ~r/^### OP trace R2 \[A\]: engine trace/))
    assert Enum.any?(traced, &(&1 =~ ~r/^### OP trace R2 \[B\] \| /))

    # Each category's file carries the other's players as sitting the round
    # out, which the engine's own lines count as a round of history.
    assert ("### OP trace R2 [A]: this is round 2; the engine counts the column of the players " <>
              "sitting it out as history, so its own lines call it round 3") in traced
  end

  test "a team Swiss round keeps the engine's report of the result it returned" do
    {t, _} =
      team_swiss(for(i <- 1..5, do: {"T#{i}", [2000 - i * 10, 1990 - i * 10]}),
        round_dates: List.duplicate("2026-09-01", 5)
      )

    pair_next!(t)

    assert %{"kind" => "team", "sections" => [%{"text" => text}]} = trace(t, 1)
    assert text =~ "pairing team round 1"
    assert text =~ "C.04.6"

    traced = trace_lines(itdx(t))
    assert "### OP trace R1: engine trace, rendered from the result the engine returned" in traced

    assert Enum.any?(
             traced,
             &(&1 =~ ~r/^### OP trace R1 \| .*team \d+ \(white on board 1\) vs\. team \d+/)
           )
  end
end
