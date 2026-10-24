defmodule PairingsEngine.TeamPrimaryScoreTest do
  @moduledoc """
  Game points as a team event's primary score (C.04.6 Art. 1.2.1): the
  standings sort by them, the team Swiss is paired by them, the TRF says so
  and reads it back, and none of it leaves FIDE mode - it only locks with
  round 1, like the rest of the scoring.
  """
  use PairingsEngine.DataCase, async: false

  import PairingsEngine.AccountsFixtures, only: [user_scope_fixture: 0]
  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Compliance, Repo, TeamStandings, TeamSwiss, Tiebreaks, Tournaments}
  alias PairingsEngine.{TrfExport, TrfImport}
  alias PairingsEngine.Tournaments.{Player, Tournament}

  # The worked example of team_standings_test.exs, three rounds of a
  # four-team round robin on two boards:
  #
  #   team  MP  GP   BB
  #   T1    3   3.5   5
  #   T2    4   4     7
  #   T3    5   4     5
  #   T4    0   ½     1
  #
  # By match points T3 leads; by game points T2 and T3 tie and the board
  # points weighted by board put T2 ahead. (Not Buchholz: a round robin
  # drops it, C.07 Art. 8.)
  defp worked_example(opts) do
    {t, _} =
      team_round_robin(
        [{"T1", [2100, 2000]}, {"T2", [2050, 1950]}, {"T3", [2000, 1900]}, {"T4", [1950, 1850]}],
        [tiebreaks: ~w(BB SB)] ++ opts
      )

    t = pair_all!(t)
    enter!(t, 1, "T1", "T4", ["1-0", "0-1"])
    enter!(t, 1, "T2", "T3", ["1-0", "1-0"])
    enter!(t, 2, "T4", "T3", ["1/2-1/2", "1-0"])
    enter!(t, 2, "T1", "T2", ["0-1", "0-1"])
    enter!(t, 3, "T2", "T4", ["1-0", "0-1"])
    enter!(t, 3, "T3", "T1", ["1/2-1/2", "0-1"])
    Repo.reload!(t)
  end

  defp names(entries), do: Enum.map(entries, & &1.team.name)

  describe "the standings" do
    test "match points first by default, game points first when the rules say so" do
      assert names(TeamStandings.standings(worked_example([]))) == ~w(T3 T2 T1 T4)

      gp = worked_example(team_primary_score: "game_points")
      entries = TeamStandings.standings(gp)

      assert names(entries) == ~w(T2 T3 T1 T4)
      assert TeamStandings.primary_code(gp) == "GP"
      assert Enum.map(entries, &TeamStandings.primary_value(&1, gp)) == [4.0, 4.0, 3.5, 0.5]
    end

    test "the primary code is MP for an individual event and by default" do
      assert TeamStandings.primary_code(%Tournament{type: "team-swiss"}) == "MP"

      assert TeamStandings.primary_code(%Tournament{
               type: "swiss",
               team_primary_score: "game_points"
             }) == "MP"
    end

    test "the FIDE default tie-breaks put the other score first" do
      assert Tiebreaks.fide_defaults_for(%Tournament{type: "team-swiss"}) ==
               ~w(MP GP DE BB SB)

      assert Tiebreaks.fide_defaults_for(%Tournament{
               type: "team-swiss",
               team_primary_score: "game_points"
             }) == ~w(GP MP DE BB SB)
    end
  end

  # Six teams on four boards, round 1 won narrowly in two matches and 4-0 in
  # the third. By match points the three winners share a score group; by
  # game points the 4-0 winner is alone at the top.
  defp swiss(opts) do
    teams = for i <- 1..6, do: {"T#{i}", Enum.map(1..4, &(2200 - i * 20 - &1))}
    {t, _} = team_swiss(teams, [boards: 4, rounds: 4] ++ opts)
    pair_next!(t)

    round = Tournaments.get_round(t.id, 1)

    round.id
    |> Tournaments.list_matches()
    |> Enum.reject(&is_nil(&1.team_b_id))
    |> Enum.zip([[1, 1, 0.5, 0], [1, 1, 1, 1], [1, 0.5, 1, 0]])
    |> Enum.each(fn {match, points} -> score!(round, match, points) end)

    Repo.reload!(t)
  end

  # Team A of `match` scores `points` on its boards, board 1 first.
  defp score!(round, match, points) do
    boards = round.pairings |> Enum.filter(&(&1.match_id == match.id)) |> Enum.sort_by(& &1.board)

    for {p, pts} <- Enum.zip(boards, points) do
      a_white? = Repo.get!(Player, p.white_player_id).team_id == match.team_a_id

      result =
        case {pts, a_white?} do
          {0.5, _} -> "1/2-1/2"
          {1, true} -> "1-0"
          {1, false} -> "0-1"
          {0, true} -> "0-1"
          {0, false} -> "1-0"
        end

      {:ok, _} = Tournaments.update_pairing_result(p, result)
    end
  end

  defp pairs(t, number) do
    round = Tournaments.get_round(t.id, number)
    by_id = t.id |> Tournaments.list_teams() |> Map.new(&{&1.id, &1.name})

    round.id
    |> Tournaments.list_matches()
    |> Enum.map(&MapSet.new([by_id[&1.team_a_id], by_id[&1.team_b_id]]))
    |> MapSet.new()
  end

  defmodule RecordingStub do
    @moduledoc "Pairs with the real engine and tells the test what it was asked."
    def pair_round(teams, opts) do
      send(Application.get_env(:pairings_engine, :team_primary_score_test_pid), {:opts, opts})
      Ainalrami.TeamPairing.pair_round(teams, opts)
    end
  end

  defp recording(fun) do
    Application.put_env(:pairings_engine, :team_pairing_module, RecordingStub)
    Application.put_env(:pairings_engine, :team_primary_score_test_pid, self())

    try do
      fun.()
    after
      Application.delete_env(:pairings_engine, :team_pairing_module)
      Application.delete_env(:pairings_engine, :team_primary_score_test_pid)
    end
  end

  describe "the team Swiss pairing" do
    test "the engine is told the primary score" do
      assert TeamSwiss.score_mode(%Tournament{}) == :match_points
      assert TeamSwiss.score_mode(%Tournament{team_primary_score: "game_points"}) == :game_points

      mp = swiss([])
      recording(fn -> pair_next!(mp) end)
      assert_received {:opts, opts}
      assert opts[:score_mode] == :match_points

      gp = swiss(team_primary_score: "game_points")
      recording(fn -> pair_next!(gp) end)
      assert_received {:opts, opts}
      assert opts[:score_mode] == :game_points
    end

    test "game points primary pairs round 2 differently from the same round 1" do
      mp = swiss([])
      gp = swiss(team_primary_score: "game_points")
      assert pairs(mp, 1) == pairs(gp, 1)

      pair_next!(mp)
      pair_next!(gp)

      refute pairs(mp, 2) == pairs(gp, 2)
    end

    test "the engine's view floats on the primary score" do
      gp = swiss(team_primary_score: "game_points")
      teams = PairingsEngine.TeamRounds.numbered_teams(gp.id)
      {field, _} = TeamSwiss.split_field(gp, teams, 2)
      input = TeamSwiss.engine_input(gp, teams, field, 2)

      # Round 1 paired every team against one on the same (zero) score, so
      # nobody floated in it, whichever score is primary.
      refute Enum.any?(input.teams, & &1.floated_last_round?)
    end
  end

  describe "FIDE mode" do
    test "either choice is FIDE's, and it locks once round 1 is paired" do
      {t, _} = team_swiss(for(i <- 1..4, do: {"T#{i}", [2000 - i, 1900 - i]}))

      assert {:ok, t} = Tournaments.update_tournament(t, %{"team_primary_score" => "game_points"})
      assert Compliance.check(t) == []
      assert Compliance.fide_mode?(t)

      pair_next!(t)
      t = Repo.reload!(t)
      assert :team_primary_score in Tournaments.fide_locked_fields(t)

      assert {:error, :locked_in_fide_mode} =
               Tournaments.update_tournament(t, %{"team_primary_score" => "match_points"})
    end

    test "an unknown value is refused" do
      {t, _} = team_swiss([{"A", [2000]}, {"B", [1900]}])

      assert {:error, changeset} =
               Tournaments.update_tournament(t, %{"team_primary_score" => "vibes"})

      assert errors_on(changeset)[:team_primary_score]
    end
  end

  describe "the TRF" do
    test "the 192 code names game points primary, and the import reads it back" do
      scope = user_scope_fixture()

      gp =
        swiss(
          team_primary_score: "game_points",
          user_id: scope.user.id,
          start_date: "2026-09-01",
          end_date: "2026-09-04",
          round_dates: ~w(2026-09-01 2026-09-02 2026-09-03 2026-09-04)
        )

      {:ok, text} = TrfExport.export(gp, nil, dialect: :engine)
      assert text =~ ~r/^192 FIDE_TEAM_TYPEA_GP_MP\r?$/m

      {:ok, imported, _warnings} = TrfImport.import_text(text, scope)
      assert imported.team_primary_score == "game_points"

      mp =
        swiss(
          name: "Second league",
          user_id: scope.user.id,
          start_date: "2026-09-01",
          end_date: "2026-09-04",
          round_dates: ~w(2026-09-01 2026-09-02 2026-09-03 2026-09-04)
        )

      {:ok, text} = TrfExport.export(mp, nil, dialect: :engine)
      assert text =~ ~r/^192 FIDE_TEAM_TYPEA_MP_GP\r?$/m

      {:ok, imported, _warnings} = TrfImport.import_text(text, scope)
      assert imported.team_primary_score == "match_points"
    end
  end
end
