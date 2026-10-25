defmodule PairingsEngine.TrfItdxTest do
  @moduledoc """
  The three TRF26 files, one job each: Send (records), the copy (Send's
  records plus marks and notes) and the ITDX file (`?`, `X`, the notes and
  the OpenPairings block, for handing a running event to another program).
  """
  use PairingsEngine.DataCase, async: false

  alias PairingsEngine.{Pairing, PostponedGames, Repo, TrfExport, TrfImport, Tournaments}
  alias PairingsEngine.Accounts.{Scope, User}
  alias PairingsEngine.Tournaments.Tournament

  defp tournament(names, attrs \\ []) do
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
              postponed_games: true,
              fide_compliance_lost_round: 0,
              round_dates: ["2026-09-01", "2026-09-08", "2026-09-15"]
            },
            Map.new(attrs)
          )
        )
      )

    players =
      for {name, i} <- Enum.with_index(names), into: %{} do
        {:ok, p} =
          Tournaments.create_player(t.id, %{
            tournament_id: t.id,
            name: name,
            fide_rating: 2100 - 100 * i,
            fide_id: 20_000_000 + i
          })

        {name, p}
      end

    {t, players}
  end

  defp pair!(t) do
    {:ok, round} = Pairing.pair_next_round(Repo.reload!(t))
    Tournaments.get_round(t.id, round.number)
  end

  defp result!(pairing, result) do
    {:ok, updated} =
      Tournaments.update_pairing_result(
        pairing,
        result,
        acknowledged: PostponedGames.acknowledgement_ids()
      )

    updated
  end

  # Round 1: one board postponed (or played), the others played. Round 2
  # paired and not played.
  defp event(postponed?) do
    {t, players} = tournament(~w(Alice Bob Carol Dave Erin Frank))
    round1 = pair!(t)
    [first | rest] = round1.pairings
    if postponed?, do: result!(first, "*"), else: result!(first, "1-0")
    for p <- rest, do: result!(p, "1-0")
    _round2 = pair!(t)
    {Repo.reload!(t), players}
  end

  defp lines(text), do: String.split(text, "\r\n")
  defp records(text), do: Enum.filter(lines(text), &String.starts_with?(&1, "001"))
  defp notes(text), do: Enum.filter(lines(text), &String.starts_with?(&1, "###"))
  defp block(line, r), do: line |> String.slice(91 + (r - 1) * 10, 10) |> String.trim_trailing()

  defp user_scope do
    user =
      Repo.insert!(%User{
        email: "user#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    Scope.for_user(user)
  end

  describe "the copy" do
    test "is Send's records plus the marks and every note, with no ?" do
      {t, _} = event(true)

      {:ok, sent} = TrfExport.export(t, [1], for: :rating)
      {:ok, copy} = TrfExport.export(t, [1], copy: true)

      assert records(copy) == records(sent)
      refute Enum.any?(records(copy), &(&1 =~ "?"))
      refute copy =~ ~r/^162 .*X /m
      assert copy =~ "DDD SSSS"
      assert copy =~ "### COPY - NOT FOR RATING"
      assert copy =~ "### FIDE mode exited before Round 1 was paired"
      assert Enum.any?(notes(copy), &(&1 =~ ~r/^### Postponed @ Round 1: \d+-\d+/))
      refute copy =~ "### OP "
      refute sent =~ "###"
    end

    test "has no Postponed note when nothing is open" do
      {t, _} = event(false)
      {:ok, copy} = TrfExport.export(t, [1], copy: true)
      refute copy =~ "Postponed @"
    end
  end

  describe "the ITDX file" do
    test "writes ? for the postponed game and the unplayed boards, X the draw" do
      {t, _} = event(true)
      {:ok, text} = TrfExport.export(t, nil, itdx: true)

      assert text =~ "### ITDX - NOT FOR RATING"
      assert text =~ ~r/^162 .*X 0\.5/m
      assert Enum.any?(records(text), &(block(&1, 1) =~ "?"))
      assert Enum.any?(records(text), &(block(&1, 2) =~ "?"))
      assert Enum.any?(notes(text), &(&1 =~ ~r/^### Unplayed @ Round 2: /))
    end

    test "with only unplayed boards, X is 0" do
      {t, _} = event(false)
      {:ok, text} = TrfExport.export(t, nil, itdx: true)

      assert text =~ ~r/^162 .*X 0\.0/m
      assert Enum.all?(records(text), &(not String.contains?(block(&1, 1), "?")))
      assert Enum.any?(records(text), &(block(&1, 2) =~ "?"))
    end

    test "is made in FIDE mode with a postponed game open, where the copy is refused" do
      {t, _} = event(true)
      t = t |> Ecto.Changeset.change(fide_compliance_lost_round: nil) |> Repo.update!()

      assert {:error, {:open_postponed, _}} = TrfExport.export(t, [1], copy: true)
      assert {:ok, text} = TrfExport.export(t, [1], itdx: true)
      assert text =~ "ITDX - NOT FOR RATING"
    end

    test "carries the OpenPairings block: present, ASCII, one fact per line, no personal data" do
      {t, _} = event(true)
      {:ok, text} = TrfExport.export(t, nil, itdx: true)
      {:ok, copy} = TrfExport.export(t, nil, copy: true)
      {:ok, sent} = TrfExport.export(t, nil, for: :rating)

      op = Enum.filter(notes(text), &String.starts_with?(&1, "### OP "))
      assert [header | _] = op

      assert header =~
               ~r/^### OP block: written by OpenPairings \S+ \(Ainalrami \S+\); informational only, not read back$/

      assert Enum.any?(op, &(&1 =~ "OP setting pairing_system: swiss"))
      assert Enum.any?(op, &(&1 =~ "OP setting tiebreaks: BH SB"))
      assert Enum.any?(op, &(&1 =~ ~r/^### OP round 2: status /))

      for line <- op, do: assert(line =~ ~r/^[\x20-\x7e]+$/)
      refute Enum.join(op, "\n") =~ "@"
      refute Enum.join(op, "\n") =~ "Alice"

      refute copy =~ "### OP "
      refute sent =~ "### OP "
    end

    test "is read back to the same pairings, colours and scores; the block changes nothing" do
      {t, _} = event(true)
      {:ok, text} = TrfExport.export(t, nil, itdx: true)

      assert {:ok, imported, _warnings} = TrfImport.import_text(text, user_scope())
      imported = Repo.reload!(imported)

      boards = fn tournament, n ->
        ranks =
          tournament.id
          |> Tournaments.list_players()
          |> Map.new(&{&1.id, &1.pairing_number})

        for p <- Tournaments.get_round(tournament.id, n).pairings do
          {ranks[p.white_player_id], ranks[p.black_player_id], p.result}
        end
        |> Enum.sort()
      end

      for n <- [1, 2] do
        strip = fn boards -> Enum.map(boards, &Tuple.delete_at(&1, 2)) end
        assert strip.(boards.(imported, n)) == strip.(boards.(t, n))
      end

      # Round 2 came back as boards still being played, not as postponed games.
      assert Enum.all?(boards.(imported, 2), fn {_, _, result} -> result == "" end)
      assert Enum.count(boards.(imported, 1), fn {_, _, result} -> result == "*" end) == 1

      {:ok, again} = TrfExport.export(imported, nil, itdx: true)
      assert records(again) == records(text)
    end
  end
end
