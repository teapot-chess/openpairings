defmodule PairingsEngine.TeamDrawTest do
  @moduledoc """
  The order of the teams drawn by lot before round 1
  (`Tournaments.draw_team_order/1`, C.04.6 Art. 1.1.2): a permutation of the
  teams, kept by round 1, recorded, refused once the numbers are frozen, and
  forgotten as soon as somebody changes the order by other means.
  """
  use PairingsEngine.DataCase, async: false

  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Compliance, Repo, Tournaments}

  defp event(n \\ 6) do
    teams = for i <- 1..n, do: {"T#{i}", [2100 - i * 10, 2000 - i * 10]}
    team_swiss(teams, team_rating_method: "manual", teams_ordered_by_hand: false)
  end

  defp order(t), do: t.id |> Tournaments.list_teams() |> Enum.map(& &1.name)

  test "puts every team in a new place exactly once and records the draw" do
    {t, _} = event()
    assert {:ok, drawn} = Tournaments.draw_team_order(t)

    t = Repo.reload!(t)
    assert Enum.sort(Enum.map(drawn, & &1.name)) == ~w(T1 T2 T3 T4 T5 T6)
    assert Enum.map(drawn, & &1.name) == order(t)
    assert Enum.map(drawn, & &1.seed) == Enum.to_list(1..6)
    assert t.teams_ordered_by_hand
    assert %DateTime{} = t.teams_drawn_at
    assert Compliance.fide_mode?(t)
  end

  test "round 1 numbers the teams in the drawn order rather than by rating" do
    {t, _} = event()
    {:ok, drawn} = Tournaments.draw_team_order(t)
    pair_next!(t)

    numbered =
      t.id |> Tournaments.list_teams() |> Enum.sort_by(& &1.pairing_number) |> Enum.map(& &1.name)

    assert numbered == Enum.map(drawn, & &1.name)
  end

  test "is a lot: twenty draws of six teams do not all come out the same" do
    {t, _} = event()

    orders =
      for _ <- 1..20 do
        {:ok, drawn} = Tournaments.draw_team_order(t)
        Enum.map(drawn, & &1.name)
      end

    assert orders |> Enum.uniq() |> length() > 1
  end

  test "refused with fewer than two teams and once round 1 is paired" do
    {lonely, _} = event(1)
    assert {:error, :too_few_teams} = Tournaments.draw_team_order(lonely)

    {t, _} = event(4)
    pair_next!(t)
    assert {:error, :teams_frozen} = Tournaments.draw_team_order(Repo.reload!(t))
  end

  test "moving a team or ordering by rating afterwards forgets the draw" do
    {t, [t1 | _]} = event()
    {:ok, _} = Tournaments.draw_team_order(t)
    t = Repo.reload!(t)

    {:ok, _} = Tournaments.move_team(t, Repo.reload!(t1), :down)
    t = Repo.reload!(t)
    assert t.teams_drawn_at == nil
    assert t.teams_ordered_by_hand

    {:ok, _} = Tournaments.draw_team_order(t)
    {:ok, _} = Tournaments.seed_teams_by_rating(Repo.reload!(t))
    t = Repo.reload!(t)
    assert t.teams_drawn_at == nil
    refute t.teams_ordered_by_hand
  end
end
