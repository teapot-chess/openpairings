defmodule PairingsEngine.TrfRatingRecordsTest do
  @moduledoc """
  The file SENT FOR RATING reports the games of its rounds and nothing the
  event has not played: no `240` for a round nobody has paired, no round
  column past the file's last round, none of the pairing records (`250`
  virtual points, `260` players kept apart, `299` extra points), and a
  points column that is what its own columns add up to. The same file is
  generated for a spread of tournaments - byes entered ahead, a withdrawal,
  a late entrant, a postponed game, Baku, prohibitions, a team event - and
  each is held to the same list. The file also reads back
  (`Ainalrami.Trf.parse/1`).

  The ITDX file and the engine's dialect keep the future byes and the
  pairing records: they are for pairing the round after.
  """
  use PairingsEngine.DataCase, async: true

  import PairingsEngine.TeamFixtures

  alias Ainalrami.Trf
  alias PairingsEngine.{Pairing, PostponedGames, Repo, TrfExport, Tournaments}
  alias PairingsEngine.Tournaments.Tournament

  @dates ~w(2026-09-01 2026-09-08 2026-09-15 2026-09-22 2026-09-29 2026-10-06 2026-10-13)

  defp swiss(attrs \\ []) do
    t =
      Repo.insert!(
        struct(
          Tournament,
          Map.merge(
            %{
              name: "Seven rounds",
              type: "swiss",
              rounds_count: 7,
              federation: "BEL",
              initial_colour: "white",
              round_dates: @dates
            },
            Map.new(attrs)
          )
        )
      )

    players =
      for n <- 1..10 do
        {:ok, p} =
          Tournaments.create_player(t.id, %{
            "name" => "P#{n}, X",
            "fide_rating" => 2400 - n * 50,
            "national_rating" => 1900 - n,
            "federation" => "BEL",
            "club" => "Club #{rem(n, 3)}"
          })

        p
      end

    {t, players}
  end

  defp pair_and_play!(t, rounds, results \\ ~w(1-0 0-1 1/2-1/2)) do
    for r <- 1..rounds do
      {:ok, round} = Pairing.pair_next_round(Repo.reload!(t))
      round = Tournaments.get_round(t.id, round.number)

      for {board, i} <- Enum.with_index(round.pairings) do
        if board.black_player_id do
          result = Enum.at(results, rem(i + r, length(results)))

          {:ok, _} =
            Tournaments.update_pairing_result(board, result,
              acknowledged: PostponedGames.acknowledgement_ids()
            )
        end
      end
    end

    Repo.reload!(t)
  end

  @names [
    "byes entered ahead",
    "byes entered ahead, a slice that is the whole file",
    "byes entered ahead, a slice",
    "a withdrawal",
    "a late entrant",
    "Baku acceleration",
    "extra points in acceleration mode",
    "3-1-0 points",
    "prohibitions",
    "a postponed game",
    "a team swiss"
  ]

  # name => fn -> {tournament, rounds_spec}
  defp scenarios do
    %{
      "byes entered ahead" => fn ->
        {t, ps} = swiss()
        {:ok, _} = Tournaments.update_player(Enum.at(ps, 0), %{absent_rounds: "7"})
        {:ok, _} = Tournaments.update_player(Enum.at(ps, 1), %{absent_rounds: "5,6"})
        {pair_and_play!(t, 4), nil}
      end,
      "byes entered ahead, a slice that is the whole file" => fn ->
        {t, ps} = swiss()
        {:ok, _} = Tournaments.update_player(Enum.at(ps, 4), %{absent_rounds: "6,7"})
        {pair_and_play!(t, 3), [1, 2, 3]}
      end,
      "byes entered ahead, a slice" => fn ->
        {t, ps} = swiss()
        {:ok, _} = Tournaments.update_player(Enum.at(ps, 4), %{absent_rounds: "5,7"})
        {pair_and_play!(t, 4), [1, 2]}
      end,
      "a withdrawal" => fn ->
        {t, ps} = swiss()
        t = pair_and_play!(t, 2)
        {:ok, _} = Tournaments.update_player(Enum.at(ps, 3), %{status: "withdrawn"})
        {:ok, _} = Tournaments.update_player(Enum.at(ps, 5), %{absent_rounds: "6"})
        {pair_and_play!(t, 2), nil}
      end,
      "a late entrant" => fn ->
        {t, ps} = swiss(late_entry_absences: true)
        t = pair_and_play!(t, 2)

        {:ok, _} =
          Tournaments.create_player(t.id, %{
            "name" => "Late, Lena",
            "fide_rating" => 2000,
            "federation" => "BEL"
          })

        {:ok, _} = Tournaments.update_player(Enum.at(ps, 2), %{absent_rounds: "7"})
        {pair_and_play!(t, 2), nil}
      end,
      "Baku acceleration" => fn ->
        {t, ps} = swiss(acceleration: "baku")
        {:ok, _} = Tournaments.update_player(Enum.at(ps, 0), %{absent_rounds: "7"})
        {pair_and_play!(t, 4), nil}
      end,
      "extra points in acceleration mode" => fn ->
        {t, ps} = swiss(extra_points_mode: "acceleration", count_extra_points: true)

        for p <- Enum.take(ps, 4),
            do: {:ok, _} = Tournaments.update_player(p, %{"extra_points" => 1.0})

        {:ok, _} = Tournaments.update_player(Enum.at(ps, 9), %{absent_rounds: "6"})
        {pair_and_play!(t, 3), nil}
      end,
      "3-1-0 points" => fn ->
        {t, ps} = swiss(points_win: 3.0, points_draw: 1.0, points_loss: 0.0, bye_value: 3.0)
        {:ok, _} = Tournaments.update_player(Enum.at(ps, 2), %{absent_rounds: "5"})
        {pair_and_play!(t, 4), nil}
      end,
      "prohibitions" => fn ->
        {t, ps} = swiss()
        {:ok, _} = Tournaments.add_forbidden_pairing(t, Enum.at(ps, 2).id, Enum.at(ps, 3).id)
        t = pair_and_play!(t, 2)
        {:ok, _} = Tournaments.add_forbidden_pairing(t, Enum.at(ps, 4).id, Enum.at(ps, 5).id)
        {pair_and_play!(t, 2), nil}
      end,
      "a postponed game" => fn ->
        {t, ps} = swiss(postponed_games: true, fide_compliance_lost_round: 0)
        {:ok, _} = Tournaments.update_player(Enum.at(ps, 0), %{absent_rounds: "7"})
        {pair_and_play!(t, 2, ~w(*W 1-0 0-1)), nil}
      end,
      "a team swiss" => fn ->
        {t, _} =
          team_swiss(
            [
              {"Antwerp", [2210, 2105]},
              {"Brugge", [2150, 2000]},
              {"Charleroi", [1900, 1850]},
              {"Deurne", [1800, 1750]},
              {"Eupen", [1700, 1650]},
              {"Genk", [1600, 1550]}
            ],
            rounds: 5,
            federation: "BEL",
            round_dates: Enum.take(@dates, 5)
          )

        for _ <- 1..2 do
          round = pair_next!(t)
          round = Tournaments.get_round(t.id, round.number)

          for b <- round.pairings, b.black_player_id do
            {:ok, _} = Tournaments.update_pairing_result(b, "1-0")
          end
        end

        {Repo.reload!(t), nil}
      end
    }
  end

  defp lines(text), do: String.split(text, "\r\n", trim: true)
  defp records(text, code), do: Enum.filter(lines(text), &String.starts_with?(&1, code <> " "))

  defp player_lines(text), do: records(text, "001")

  defp blocks(line) do
    line
    |> String.slice(91..-1//1)
    |> String.codepoints()
    |> Enum.chunk_every(10)
    |> Enum.map(&(&1 |> Enum.join() |> String.trim_trailing()))
  end

  describe "the file for rating, whatever the tournament" do
    for name <- @names do
      test "#{name}" do
        {t, spec} = Map.fetch!(scenarios(), unquote(name)).()
        paired = Pairing.paired_rounds_count(t.id)
        file_rounds = if spec, do: Enum.max(spec), else: paired

        {:ok, text} = TrfExport.export(t, spec, for: :rating)

        # Reports games, not what comes next.
        assert records(text, "240") == []
        # Nor how the next round gets paired.
        for code <- ~w(250 260 299), do: assert(records(text, code) == [], code)

        # Team records name rounds too (`300` lineups, `330` forfeits).
        for line <- records(text, "300"), do: assert(round_at(line, 4, 6) <= file_rounds)
        for line <- records(text, "330"), do: assert(round_at(line, 7, 9) <= file_rounds)

        # Nothing past the file's last round, and no empty last round.
        cols = player_lines(text) |> Enum.map(&blocks/1)
        assert Enum.all?(cols, &(length(&1) <= file_rounds))

        assert Enum.any?(cols, fn b -> Enum.at(b, file_rounds - 1, "") != "" end),
               "last round column is empty for everybody"

        # Round dates: only the file's rounds.
        for line <- records(text, "132") do
          assert line |> String.slice(91..-1//1) |> String.trim() |> String.split() |> length() <=
                   file_rounds
        end

        assert_points_are_the_columns(text)

        # The legend line stays.
        assert Enum.any?(lines(text), &String.starts_with?(&1, "DDD SSSS sTTT NNNN"))

        # It reads back, and the copy is this file plus its marks.
        assert %{players: [_ | _]} = Trf.parse(text)
        {:ok, copy} = TrfExport.export(t, spec, copy: true)

        assert copy
               |> String.split("\r\n")
               |> Enum.reject(&String.starts_with?(&1, "###"))
               |> Enum.join("\r\n") ==
                 text
      end
    end
  end

  defp round_at(line, from, to),
    do: line |> String.slice(from, to - from + 1) |> String.trim() |> String.to_integer()

  defp assert_points_are_the_columns(text) do
    parsed = Trf.parse(text)
    system = parsed.tournament[:point_system] || Trf.default_point_system()

    for p <- parsed.players do
      sum =
        Enum.reduce(p.games, 0.0, fn g, acc ->
          case g.result do
            r when r in [nil, ""] -> acc
            _ -> acc + Trf.points_for_game(g, system)
          end
        end)

      assert_in_delta p.points,
                      sum,
                      0.001,
                      "player #{p.rank}: points column #{p.points}, columns add up to #{sum}"
    end
  end

  describe "the other files keep the byes entered ahead" do
    test "the ITDX file and the engine's dialect carry them, the copy and the sent file do not" do
      {t, ps} = swiss()
      {:ok, _} = Tournaments.update_player(Enum.at(ps, 0), %{absent_rounds: "7"})
      t = pair_and_play!(t, 4)

      {:ok, itdx} = TrfExport.export(t, nil, itdx: true)
      assert [_ | _] = records(itdx, "240")

      {:ok, engine} = TrfExport.export(t, nil, dialect: :engine)
      assert Enum.any?(player_lines(engine), &(&1 |> blocks() |> length() == 7))

      {:ok, plain} = TrfExport.export(t, nil, [])
      assert [_ | _] = records(plain, "240")

      {:ok, sent} = TrfExport.export(t, nil, for: :rating)
      {:ok, copy} = TrfExport.export(t, nil, copy: true)
      assert records(sent, "240") == []
      assert records(copy, "240") == []
    end
  end

  describe "the other files keep the pairing records" do
    for {name, code} <- [
          {"Baku acceleration", "250"},
          {"prohibitions", "260"},
          {"extra points in acceleration mode", "299"}
        ] do
      test "#{code} for #{name}" do
        {t, spec} = Map.fetch!(scenarios(), unquote(name)).()

        {:ok, itdx} = TrfExport.export(t, spec, itdx: true)
        {:ok, plain} = TrfExport.export(t, spec, [])
        {:ok, sent} = TrfExport.export(t, spec, for: :rating)

        assert [_ | _] = records(itdx, unquote(code))
        assert [_ | _] = records(plain, unquote(code))
        assert records(sent, unquote(code)) == []
      end
    end
  end
end
