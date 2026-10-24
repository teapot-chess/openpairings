defmodule PairingsEngine.TeamTpnTest do
  @moduledoc """
  Team numbers corrected until round 4 (C.04.2 2.3 as C.04.6 Art. 1.1 takes
  it): the exchange of two teams of equal rating, the regeneration from the
  team ratings, the lock from round 5, and the average rating fielded.
  """
  use PairingsEngine.DataCase, async: false

  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Compliance, Repo, TeamStandings, TeamTpn, Tournaments}

  defp event(n \\ 6, opts \\ []) do
    teams = for i <- 1..n, do: {"T#{i}", [2100 - i * 10, 2000 - i * 10]}
    team_swiss(teams, [boards: 2, rounds: 5] ++ opts)
  end

  defp play!(t, round) do
    Tournaments.get_round(t.id, round).pairings
    |> Enum.filter(&(&1.result == "" and &1.black_player_id))
    |> Enum.each(fn p -> {:ok, _} = Tournaments.update_pairing_result(p, "1-0") end)
  end

  defp rate!(team, rating),
    do: {:ok, _} = Tournaments.update_team(team, %{"rating_override" => to_string(rating)})

  defp numbers(t),
    do: t.id |> Tournaments.list_teams() |> Map.new(&{&1.name, &1.pairing_number})

  test "nothing applies before round 1, or to a round robin" do
    {t, _} = event()
    refute TeamTpn.editable?(t)
    assert {:error, :locked} = TeamTpn.regenerate(t)

    {rr, _} = team_round_robin([{"A", [2000, 1900]}, {"B", [1950, 1850]}])
    rr = pair_all!(rr)
    refute TeamTpn.applies?(rr)
    assert {:error, :not_swiss} = TeamTpn.regenerate(rr)
  end

  test "numbers that follow the ratings are not reported, and a regeneration changes nothing" do
    {t, _} = event()
    pair_next!(t)
    t = Repo.reload!(t)

    assert TeamTpn.out_of_place(t) == []
    assert {:unchanged, _} = TeamTpn.regenerate(t)
    assert TeamTpn.regeneration_changes(t) == []
  end

  test "a corrected rating shows who is out of place; equal ratings never are" do
    {t, [t1, t2, t3 | _]} = event()
    pair_next!(t)
    rate!(t1, 1500)
    rate!(t2, 2000)
    rate!(t3, 2000)
    t = Repo.reload!(t)

    out = TeamTpn.out_of_place(t)
    assert Enum.map(out, & &1.team.name) |> Enum.member?("T1")
    assert Enum.find(out, &(&1.team.name == "T1")).expected == 6

    refute Enum.any?(
             out,
             &(&1.team.name in ["T2", "T3"] and &1.expected in [2, 3] and &1.number in [2, 3])
           )
  end

  test "an exchange needs equal ratings and moves exactly those two numbers" do
    {t, [t1, t2, t3 | _]} = event()
    pair_next!(t)
    rate!(t2, 2000)
    rate!(t3, 2000)
    t = Repo.reload!(t)

    assert {:error, :different_ratings} = TeamTpn.exchange(t, t1.id, t2.id)
    assert {:ok, _} = TeamTpn.exchange(t, t2.id, t3.id)
    assert %{"T2" => 3, "T3" => 2, "T1" => 1} = Map.take(numbers(t), ~w(T1 T2 T3))
    assert Repo.reload!(t2).seed == 3
    assert {:error, :not_found} = TeamTpn.exchange(t, t2.id, 0)
  end

  test "a regeneration follows the ratings, keeps equal ones in order, and stays in FIDE mode" do
    {t, [t1, t2, t3 | _]} = event()
    pair_next!(t)
    rate!(t1, 1500)
    rate!(t2, 2000)
    rate!(t3, 2000)
    t = Repo.reload!(t)

    changes = TeamTpn.regeneration_changes(t)

    assert Enum.map(changes, fn {team, old, new} -> {team.name, old, new} end)
           |> Enum.member?({"T1", 1, 6})

    assert {:ok, _} = TeamTpn.regenerate(t)
    n = numbers(t)
    assert n["T1"] == 6
    assert n["T2"] < n["T3"]
    assert Compliance.fide_mode?(Repo.reload!(t))
    assert Repo.reload!(t).fide_compliance_lost_round == nil
    assert {:unchanged, _} = TeamTpn.regenerate(Repo.reload!(t))
  end

  test "from round 4 paired nothing renumbers" do
    {t, [t1, t2 | _]} = event(8)

    for round <- 1..4 do
      pair_next!(t)
      play!(t, round)
      if round == 3, do: assert(TeamTpn.editable?(Repo.reload!(t)))
    end

    t = Repo.reload!(t)
    refute TeamTpn.editable?(t)
    assert {:error, :locked} = TeamTpn.regenerate(t)
    assert {:error, :locked} = TeamTpn.exchange(t, t1.id, t2.id)
    assert TeamTpn.out_of_place(t) == []
  end

  describe "the average rating fielded" do
    test "is the mean of the rated players seated, per side and per team" do
      {t, [t1, t2 | _]} = event(4)
      pair_next!(t)
      play!(t, 1)
      t = Repo.reload!(t)
      matches = TeamStandings.matches(t)

      by_match = TeamStandings.fielded_ratings(t, matches)
      assert map_size(by_match) == 2

      # Round 1: T1 against T3, T2 against T4. A team's two boards are its
      # two players, 2100 - 10 i and 2000 - 10 i: the mean is 2050 - 10 i.
      {a, b} = Map.fetch!(by_match, hd(matches).match_id)
      assert {a, b} == {2040, 2020}

      latest = TeamStandings.latest_fielded_ratings(t, matches)
      assert latest[t1.id] == 2040
      assert latest[t2.id] == 2030
    end

    test "an unrated player is left out of the mean, and nobody rated is nil" do
      {t, [t1, _t2 | _]} = event(2)

      for player <- Tournaments.team_roster(t.id, t1.id) do
        player |> Ecto.Changeset.change(fide_rating: 0, national_rating: 0) |> Repo.update!()
      end

      pair_next!(t)
      t = Repo.reload!(t)

      {a, b} =
        t
        |> TeamStandings.matches()
        |> then(&TeamStandings.fielded_ratings(t, &1))
        |> Map.values()
        |> hd()

      assert a == nil
      assert b == 2030
    end
  end
end
