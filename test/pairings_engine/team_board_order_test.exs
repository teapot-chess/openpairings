defmodule PairingsEngine.TeamBoardOrderTest do
  @moduledoc """
  The tournament's *Board order* (`team_board_order`): "roster" keeps the
  Olympiad rule that nobody sits above a player listed higher; "free" lets
  the arbiter put any roster player on any board of a line-up, for each round.
  """
  use PairingsEngine.DataCase, async: false

  import Ecto.Query
  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Compliance, Repo, TeamMatches, Tournaments, TrfExport}
  alias PairingsEngine.Tournaments.{Pairing, Player}

  defp player(t, name),
    do: Repo.one!(from p in Player, where: p.tournament_id == ^t.id and p.name == ^name)

  defp ids(t, names), do: Enum.map(names, &player(t, &1).id)

  defp match(attrs \\ []) do
    {t, _} =
      team_round_robin(
        [{"A", [2100, 2000, 1900, 1800]}, {"B", [2050, 1950, 1850, 1750]}],
        [boards: 3, rounds_count: 1] ++ attrs
      )

    t = pair_all!(t)
    {m, _boards} = match_between(t, 1, "A", "B")
    {t, m}
  end

  test "the default is the roster's order, and refuses a player above one listed higher" do
    {t, m} = match()
    assert t.team_board_order == "roster"
    b = TeamMatches.lineups(t, m).b

    assert {:error, {:board_order, upper, lower}} =
             TeamMatches.set_lineups(t, m, ids(t, ["A 2", "A 1", "A 3"]), b)

    assert {upper.name, lower.name} == {"A 2", "A 1"}
  end

  test "chosen for each round: any roster player, a reserve included, on any board" do
    {t, m} = match(team_board_order: "free")
    b = TeamMatches.lineups(t, m).b

    assert {:ok, _} = TeamMatches.set_lineups(t, m, ids(t, ["A 4", "A 1", "A 3"]), b)

    lineups = TeamMatches.lineups(t, m)
    assert lineups.a == ids(t, ["A 4", "A 1", "A 3"])

    board1 = Repo.one!(from p in Pairing, where: p.match_id == ^m.id and p.board == 1)
    assert board1.white_player_id == player(t, "A 4").id

    # A player twice is still refused.
    assert {:error, {:twice, _}} =
             TeamMatches.set_lineups(t, m, ids(t, ["A 1", "A 1", "A 3"]), b)
  end

  test "the pairing still seats the roster in roster order" do
    {t, m} = match(team_board_order: "free")
    lineups = TeamMatches.lineups(t, m)
    assert lineups.a == ids(t, ["A 1", "A 2", "A 3"])
  end

  test "in FIDE mode the setting is locked once round 1 is paired" do
    {t, _m} = match()
    assert Compliance.fide_mode?(t)
    assert :team_board_order in Tournaments.fide_locked_fields(t)

    assert Tournaments.update_tournament(t, %{"team_board_order" => "free"},
             unlock: [:team_board_order]
           ) == {:error, :locked_in_fide_mode}

    assert Repo.reload!(t).team_board_order == "roster"

    {:ok, t} = Tournaments.leave_fide_mode(t)
    assert {:ok, t} = Tournaments.update_tournament(t, %{"team_board_order" => "free"})
    assert t.team_board_order == "free"
  end

  test "before round 1 the setting is free to change" do
    {t, _} = team_round_robin([{"A", [2000, 1900]}, {"B", [1950, 1850]}])
    assert {:ok, t} = Tournaments.update_tournament(t, %{"team_board_order" => "free"})
    assert t.team_board_order == "free"

    assert {:error, %Ecto.Changeset{}} =
             Tournaments.update_tournament(t, %{"team_board_order" => "nonsense"})
  end

  test "the TRF carries the line-up actually played: the games name the opponents" do
    {t, m} = match(team_board_order: "free")
    b = TeamMatches.lineups(t, m).b
    {:ok, _} = TeamMatches.set_lineups(t, m, ids(t, ["A 4", "A 1", "A 3"]), b)

    Tournaments.get_round(t.id, 1).pairings
    |> Enum.filter(&(&1.match_id == m.id))
    |> Enum.each(fn p -> {:ok, _} = Tournaments.update_pairing_result(p, "1-0") end)

    t =
      t
      |> Repo.reload!()
      |> Ecto.Changeset.change(
        start_date: "2026-09-01",
        end_date: "2026-09-05",
        round_dates: ["2026-09-01"]
      )
      |> Repo.update!()

    {:ok, text} = TrfExport.export(t, nil)

    a4 = player(t, "A 4")
    b1 = player(t, "B 1")

    line =
      text |> String.split("\n") |> Enum.find(&(String.starts_with?(&1, "001") and &1 =~ "A 4"))

    assert line
    # A 4 sits on board 1 against B 1: the game column names B 1's rank.
    a4 = Repo.reload!(a4)
    b1 = Repo.reload!(b1)
    assert line =~ String.pad_leading(Integer.to_string(b1.pairing_number), 4)
    assert a4.pairing_number
  end
end
