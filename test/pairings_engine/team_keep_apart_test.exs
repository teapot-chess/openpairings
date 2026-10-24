defmodule PairingsEngine.TeamKeepApartTest do
  @moduledoc """
  Team pairing rules (Ainalrami 0.46.0's `:forbidden_pairs` / `:soft_pairs`):
  teams of the same club, named teams, hard or wish, with round windows;
  the unpairable round named by team; FIDE mode treating them as it treats
  the individual rules; and the team records of the TRF.
  """
  use PairingsEngine.DataCase, async: false

  import ExUnit.CaptureIO
  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Exclusions, Pairing, Repo, TrfExport, TrfImport, Tournaments}

  @dates ~w(2026-09-01 2026-09-02 2026-09-03 2026-09-04)

  # `clubs` per team, in order T1..Tn ("" for none).
  defp event(clubs, opts \\ []) do
    teams =
      for {_club, i} <- Enum.with_index(clubs, 1), do: {"T#{i}", [2100 - i * 10, 2000 - i * 10]}

    {t, created} = team_swiss(teams, [boards: 2, rounds: 3, round_dates: @dates] ++ opts)

    for {team, club} <- Enum.zip(created, clubs), club != "" do
      {:ok, _} = Tournaments.update_team(team, %{"club" => club})
    end

    {Repo.reload!(t), Tournaments.list_teams(t.id)}
  end

  defp rule!(t, attrs) do
    {:ok, rule} =
      Tournaments.add_pairing_rule(t, Map.new(attrs, fn {k, v} -> {to_string(k), v} end))

    rule
  end

  # Who met whom in `round`, as sorted name pairs; the bye as `{name}`.
  defp meetings(t, round) do
    names = t.id |> Tournaments.list_teams() |> Map.new(&{&1.id, &1.name})
    r = Tournaments.get_round(t.id, round)

    r.id
    |> Tournaments.list_matches()
    |> Enum.map(fn m ->
      if m.team_b_id,
        do: Enum.sort([names[m.team_a_id], names[m.team_b_id]]),
        else: [names[m.team_a_id]]
    end)
    |> Enum.sort()
  end

  defp play!(t, round) do
    Tournaments.get_round(t.id, round).pairings
    |> Enum.filter(&(&1.result == "" and &1.black_player_id))
    |> Enum.each(fn p -> {:ok, _} = Tournaments.update_pairing_result(p, "1-0") end)
  end

  describe "teams of the same club" do
    test "without a rule FIDE seats the clubmates, with it they are apart" do
      {t, _} = event(["Gistel", "Brugge", "", "Gistel", "Brugge", ""])
      pair_next!(t)
      assert ["T1", "T4"] in meetings(t, 1)

      {t2, _} = event(["Gistel", "Brugge", "", "Gistel", "Brugge", ""])
      rule!(t2, kind: "team_club")
      pair_next!(t2)

      round = meetings(t2, 1)
      refute ["T1", "T4"] in round
      refute ["T2", "T5"] in round
      assert length(round) == 3
    end

    test "clubs compare trimmed and case-insensitively, and a blank is no club" do
      {t, teams} = event(["Gistel", "", "", " gistel ", "", ""])
      rule = rule!(t, kind: "team_club")
      assert [[a, b]] = Exclusions.groups(rule, teams)
      assert Enum.sort([a.name, b.name]) == ["T1", "T4"]

      {t, teams} = event(["", "", "", "", "", ""])
      rule = rule!(t, kind: "team_club")
      assert Exclusions.groups(rule, teams) == []
    end

    test "a window limits the rounds, and a named club limits the clubs" do
      {t, teams} = event(["Gistel", "Brugge", "", "Gistel", "Brugge", ""])
      first = rule!(t, kind: "team_club", window: "first", window_rounds: 1)

      assert Exclusions.team_groups([first], Enum.with_index(teams, 1) |> numbered(), 1, 3, false) !=
               []

      assert Exclusions.team_groups([first], numbered(Enum.with_index(teams, 1)), 2, 3, false) ==
               []

      only = rule!(t, kind: "team_club", names: ["gistel"])
      groups = Exclusions.team_groups([only], numbered(Enum.with_index(teams, 1)), 1, 3, false)
      assert groups == [[1, 4]]
    end

    test "a wish moves a match away from clubmates, and says so" do
      {t, _} = event(["Gistel", "", "", "", "Gistel", "", "", ""])
      rule!(t, kind: "team_club", soft: true)
      round = pair_next!(t)

      refute ["T1", "T5"] in meetings(t, 1)
      assert round.explanation["keep_apart"]["soft"] == [[1, 5]]
      assert Pairing.pairing_deviations(Repo.reload!(t), 1) == [:soft_pairs]
      assert Repo.reload!(t).fide_compliance_lost_round == 1
    end

    test "in FIDE mode a wish that moves a match is asked about first" do
      {t, _} = event(["Gistel", "", "", "", "Gistel", "", "", ""])
      rule!(t, kind: "team_club", soft: true)

      assert {:error, {:fide_departure, [:soft_pairs]}} =
               Pairing.pair_next_round(Repo.reload!(t), fide_departure_guard: true)

      # Nothing was kept of the refused run.
      assert Tournaments.get_round(t.id, 1) == nil
      assert Repo.reload!(t).fide_compliance_lost_round == nil

      assert {:ok, _} = Pairing.pair_next_round(Repo.reload!(t))
      assert Repo.reload!(t).fide_compliance_lost_round == 1
    end

    test "a hard rule set before round 1 keeps the tournament in FIDE mode" do
      {t, _} = event(["Gistel", "Brugge", "", "Gistel", "Brugge", ""])
      rule!(t, kind: "team_club")

      assert {:ok, _} = Pairing.pair_next_round(Repo.reload!(t), fide_departure_guard: true)
      assert PairingsEngine.Compliance.fide_mode?(Repo.reload!(t))
    end

    test "a rule changed after round 1 is recorded and leaves FIDE mode" do
      {t, _} = event(["Gistel", "Brugge", "", "Gistel", "Brugge", ""])
      pair_next!(t)
      play!(t, 1)
      t = Repo.reload!(t)
      assert Tournaments.prohibition_change_departs?(t)

      rule!(t, kind: "team_club")
      t = Repo.reload!(t)
      refute PairingsEngine.Compliance.fide_mode?(t)
      assert [%{"what" => "rule", "round" => 2}] = t.prohibition_changes
    end
  end

  describe "teams I name" do
    test "a group keeps exactly those teams apart" do
      {t, teams} = event(["", "", "", "", "", ""])
      ids = for team <- teams, team.name in ~w(T1 T4 T5), do: team.id
      rule!(t, kind: "team_group", team_ids: ids)
      pair_next!(t)

      round = meetings(t, 1)
      refute ["T1", "T4"] in round
      refute ["T4", "T5"] in round
    end

    test "a group needs two teams of this tournament" do
      {t, teams} = event(["", "", "", ""])

      assert {:error, %Ecto.Changeset{}} =
               Tournaments.add_pairing_rule(t, %{
                 "kind" => "team_group",
                 "team_ids" => [hd(teams).id]
               })

      assert {:error, :invalid_team} =
               Tournaments.add_pairing_rule(t, %{
                 "kind" => "team_group",
                 "team_ids" => [hd(teams).id, 0]
               })

      {:ok, individual} =
        Tournaments.create_tournament(user_scope(), %{"name" => "Open", "type" => "swiss"})

      assert {:error, :not_a_team_event} =
               Tournaments.add_pairing_rule(individual, %{"kind" => "team_club"})
    end
  end

  describe "a round the groups make unpairable" do
    test "is refused and named by team, with what would unblock it" do
      {t, teams} = event(["", "", "", ""])
      rule!(t, kind: "team_group", team_ids: Enum.map(teams, & &1.id))

      assert {:error, {:team_forbidden, info}} = Pairing.pair_next_round(Repo.reload!(t))
      assert info.round == 1
      assert info.groups == [~w(T1 T2 T3 T4)]
      assert info.lifting == [~w(T1 T2 T3 T4)]
      assert Tournaments.get_round(t.id, 1) == nil

      text = PairingsEngineWeb.SettingsSupport.error_text({:team_forbidden, info})
      assert text =~ "T1, T2, T3, T4"
    end
  end

  describe "the TRF" do
    test "an engine file carries the team records, never XXP, and round-trips" do
      {t, teams} = event(["Gistel", "Brugge", "", "Gistel", "Brugge", ""])
      ids = for team <- teams, team.name in ~w(T3 T6), do: team.id
      rule!(t, kind: "team_club")

      rule!(t,
        kind: "team_group",
        team_ids: ids,
        soft: true,
        window: "range",
        window_from: 2,
        window_to: 3
      )

      pair_next!(t)
      play!(t, 1)

      {:ok, text} = TrfExport.export(Repo.reload!(t), nil, dialect: :engine)
      assert text =~ "XXO team-forbidden 1 4"
      assert text =~ "XXO team-forbidden 2 5"
      assert text =~ "XXO team-soft-pairs 3 6 @2-3"
      refute text =~ "XXP"

      # The TRF26 report is FIDE's: no team records and no 260 either.
      {:ok, report} = TrfExport.export(Repo.reload!(t))
      refute report =~ "XXO team"
      refute report =~ "\r\n260 "

      assert {:ok, imported, _notes} = TrfImport.import_text(text)
      rules = Tournaments.list_pairing_rules(imported.id)
      assert Enum.all?(rules, &(&1.kind == "team_group"))
      assert Enum.count(rules, & &1.soft) == 1

      soft = Enum.find(rules, & &1.soft)
      assert {soft.window, soft.window_from, soft.window_to} == {"range", 2, 3}
      names = imported.id |> Tournaments.list_teams() |> Map.new(&{&1.id, &1.name})
      assert soft.team_ids |> Enum.map(&names[&1]) |> Enum.sort() == ["T3", "T6"]
    end

    test "the pinned engine replays the file and keeps the teams apart" do
      {t, _} = event(["Gistel", "Brugge", "", "Gistel", "Brugge", ""])
      rule!(t, kind: "team_club")
      pair_next!(t)
      play!(t, 1)

      {:ok, text} = TrfExport.export(Repo.reload!(t), nil, dialect: :engine)

      path =
        Path.join(System.tmp_dir!(), "op_team_apart_#{System.unique_integer([:positive])}.trf")

      File.write!(path, text)

      try do
        _ =
          capture_io(:stderr, fn ->
            capture_io(fn -> send(self(), {:code, Ainalrami.CLI.run(["-c", path])}) end)
          end)

        assert_received {:code, 0}
      after
        File.rm(path)
      end
    end
  end

  defp numbered(indexed), do: Enum.map(indexed, fn {team, n} -> %{team | pairing_number: n} end)

  defp user_scope do
    user =
      Repo.insert!(%PairingsEngine.Accounts.User{
        email: "teamapart#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    PairingsEngine.Accounts.Scope.for_user(user)
  end
end
