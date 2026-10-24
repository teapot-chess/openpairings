defmodule PairingsEngine.TeamPlayerRankingTest do
  @moduledoc """
  The individual ranking of a team tournament (`TeamStandings.player_ranking/2`)
  and the series label of a team: order, shared ranks, the series filter and
  what counts as a game played.
  """
  use PairingsEngine.DataCase, async: false

  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Repo, TeamStandings, Tournaments}

  defp event do
    {t, [a, b]} =
      team_round_robin(
        [{"A", [2100, 2000, 1900]}, {"B", [2050, 1950, 1850]}],
        boards: 3,
        rounds_count: 1
      )

    {:ok, _} = Tournaments.update_team(a, %{"series" => "Reeks 1", "club" => "Alpha"})
    {:ok, _} = Tournaments.update_team(b, %{"series" => "Reeks 2"})
    {pair_all!(t), Repo.reload!(a), Repo.reload!(b)}
  end

  defp names(rows), do: Enum.map(rows, & &1.player.name)

  test "points, then percentage, then rating; level players share a rank" do
    {t, _, _} = event()
    # Team A has White on boards 1 and 3, B on board 2.
    enter!(t, 1, "A", "B", ["1-0", "1/2-1/2", "0-1"])

    ranking = TeamStandings.player_ranking(t)

    assert names(ranking) == ["A 1", "B 3", "A 2", "B 2", "B 1", "A 3"]
    assert Enum.map(ranking, & &1.rank) == [1, 1, 3, 3, 5, 5]
    assert Enum.all?(ranking, &(&1.games == 1))

    [first | _] = ranking
    assert first.points == 1.0
    assert first.percentage == 100.0
    assert first.rating == 2100
    assert first.team.name == "A"
    assert first.series == "Reeks 1"
  end

  test "the series filter keeps the players of that series' teams" do
    {t, _, _} = event()
    enter!(t, 1, "A", "B", ["1-0", "1/2-1/2", "0-1"])

    assert t |> TeamStandings.player_ranking(series: "Reeks 1") |> names() ==
             ["A 1", "A 2", "A 3"]

    assert t |> TeamStandings.player_ranking(series: "Reeks 2") |> names() ==
             ["B 3", "B 2", "B 1"]

    assert t |> TeamStandings.player_ranking(series: "") |> length() == 6
  end

  test "a forfeited board is no game played: the player is left out" do
    {t, _, _} = event()
    enter!(t, 1, "A", "B", ["1-0", "1/2-1/2", "1-0FF"])

    assert t |> TeamStandings.player_ranking() |> names() |> Enum.sort() ==
             ["A 1", "A 2", "B 1", "B 2"]
  end

  test "nothing before a result is in" do
    {t, _, _} = event()
    assert TeamStandings.player_ranking(t) == []
  end

  test "series labels are the distinct non-empty ones, sorted" do
    {t, _, _} = event()

    assert t.id |> Tournaments.list_teams() |> TeamStandings.series_labels() == [
             "Reeks 1",
             "Reeks 2"
           ]
  end

  test "a cleared series or club is stored as empty text" do
    {t, a, _} = event()
    assert {:ok, a} = Tournaments.update_team(a, %{"series" => "", "club" => ""})
    assert {a.series, a.club} == {"", ""}
    assert t.id |> Tournaments.list_teams() |> TeamStandings.series_labels() == ["Reeks 2"]
  end
end
