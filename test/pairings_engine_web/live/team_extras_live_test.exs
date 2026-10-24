defmodule PairingsEngineWeb.TeamExtrasLiveTest do
  @moduledoc """
  Teams kept apart (the rules page, the unpairable round on the Pairings
  page, FIDE mode), the printable match sheets and blank line-up forms, the
  average rating fielded, and the team numbers correctable until round 4.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Audit, Compliance, Pairing, Repo, Tournaments}

  @moduletag :capture_log

  setup :register_and_log_in_user

  defp event(scope, n \\ 6, attrs \\ []) do
    teams = for i <- 1..n, do: {"T#{i}", [2100 - i * 10, 2000 - i * 10]}

    {t, created} =
      team_swiss(
        teams,
        [boards: 2, rounds: 5, user_id: scope.user.id, round_dates: ~w(a b c d e)] ++ attrs
      )

    {t, created}
  end

  # The pairing task's reply is a message the LiveView handles on its own
  # schedule: poll its rendered output, as the team Swiss tests do.
  defp wait_html(lv, needle, tries \\ 100) do
    html = render(lv)

    cond do
      html =~ needle -> html
      tries > 0 -> Process.sleep(10) && wait_html(lv, needle, tries - 1)
      true -> flunk("gave up waiting for #{inspect(needle)}")
    end
  end

  defp play!(t, round) do
    Tournaments.get_round(t.id, round).pairings
    |> Enum.filter(&(&1.result == "" and &1.black_player_id))
    |> Enum.each(fn p -> {:ok, _} = Tournaments.update_pairing_result(p, "1-0") end)
  end

  describe "the rules page of a team Swiss" do
    test "keeps teams of a club apart, and shows no player pickers", %{conn: conn, scope: scope} do
      {t, teams} = event(scope)

      for {team, club} <- Enum.zip(teams, ["Gistel", "", "", "gistel ", "", ""]), club != "" do
        {:ok, _} = Tournaments.update_team(team, %{"club" => club})
      end

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/settings/restrictions")
      assert has_element?(lv, "#team-rules-hint")
      refute has_element?(lv, "#restrictions-players")
      refute has_element?(lv, "#restrictions-effect")

      lv
      |> form("#add-rule-form", %{
        "rule" => %{"kind" => "team_club", "soft" => "false", "window" => "all"}
      })
      |> render_submit()

      assert [rule] = Tournaments.list_pairing_rules(t.id)
      assert rule.kind == "team_club"
      assert has_element?(lv, "#rule-#{rule.id}", "Teams of the same club")
      assert has_element?(lv, "#rule-#{rule.id}", "1 pair")
    end

    test "names the teams of a group", %{conn: conn, scope: scope} do
      {t, [a, _b, c | _]} = event(scope)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/settings/restrictions")

      render_change(lv, "rule_change", %{"rule" => %{"kind" => "team_group"}})
      assert has_element?(lv, "#add-rule-form-teams")

      lv
      |> form("#add-rule-form", %{
        "rule" => %{
          "kind" => "team_group",
          "soft" => "true",
          "window" => "all",
          "team_ids" => [to_string(a.id), to_string(c.id)]
        }
      })
      |> render_submit()

      assert [%{kind: "team_group", soft: true, team_ids: ids}] =
               Tournaments.list_pairing_rules(t.id)

      assert Enum.sort(ids) == Enum.sort([a.id, c.id])
    end

    test "after round 1, in FIDE mode, a change asks twice and leaves FIDE mode", %{
      conn: conn,
      scope: scope
    } do
      {t, _} = event(scope)
      pair_next!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/settings/restrictions")

      lv
      |> form("#add-rule-form", %{
        "rule" => %{"kind" => "team_club", "soft" => "false", "window" => "all"}
      })
      |> render_submit()

      assert Tournaments.list_pairing_rules(t.id) == []
      lv |> element("#fide-gate-continue") |> render_click()
      lv |> element("#fide-gate-confirm") |> render_click()

      assert [%{from_round: 2}] = Tournaments.list_pairing_rules(t.id)
      refute Compliance.fide_mode?(Repo.reload!(t))
      assert [_] = Audit.list_for_tournament(t.id, action: "pairing_rule.added")
    end

    test "an individual tournament still offers its own rules", %{conn: conn, scope: scope} do
      {:ok, t} = Tournaments.create_tournament(scope, %{"name" => "Open", "type" => "swiss"})
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/settings/restrictions")
      refute has_element?(lv, "#team-rules-hint")
      assert has_element?(lv, "#restrictions-players")
    end
  end

  describe "the Pairings page" do
    test "names the groups that make a round unpairable", %{conn: conn, scope: scope} do
      {t, teams} = event(scope, 4)

      {:ok, _} =
        Tournaments.add_pairing_rule(t, %{
          "kind" => "team_group",
          "team_ids" => Enum.map(teams, & &1.id)
        })

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")
      lv |> element("#pair-round") |> render_click()
      html = wait_html(lv, "kept apart")

      assert html =~ "kept apart"
      assert html =~ "T1, T2, T3, T4"
      assert Tournaments.get_round(t.id, 1) == nil
    end

    test "asks before a wish moves a match in FIDE mode", %{conn: conn, scope: scope} do
      {t, teams} = event(scope, 8)
      {:ok, _} = Tournaments.update_team(Enum.at(teams, 0), %{"club" => "Gistel"})
      {:ok, _} = Tournaments.update_team(Enum.at(teams, 4), %{"club" => "Gistel"})
      {:ok, _} = Tournaments.add_pairing_rule(t, %{"kind" => "team_club", "soft" => true})

      assert {:error, {:fide_departure, [:soft_pairs]}} =
               Pairing.pair_next_round(Repo.reload!(t), fide_departure_guard: true)

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")
      lv |> element("#pair-round") |> render_click()
      _ = wait_html(lv, "fide-gate-warn")
      assert has_element?(lv, "#fide-gate-warn")
    end

    test "shows the average rating each side fielded", %{conn: conn, scope: scope} do
      {t, _} = event(scope)
      pair_next!(t)

      [match | _] =
        t.id |> Tournaments.get_round(1) |> Map.fetch!(:id) |> Tournaments.list_matches()

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")
      assert has_element?(lv, "#match-avg-elo-#{match.id}", " - ")
      refute has_element?(lv, "#match-avg-elo-#{match.id}", "-  -")
    end
  end

  describe "team numbers until round 4" do
    defp rate!(team, rating),
      do: {:ok, _} = Tournaments.update_team(team, %{"rating_override" => to_string(rating)})

    test "the Pairings page warns, and the Teams page exchanges and regenerates", %{
      conn: conn,
      scope: scope
    } do
      {t, [t1, t2, t3 | _]} = event(scope)
      pair_next!(t)
      play!(t, 1)

      rate!(t1, 1500)
      rate!(t2, 2000)
      rate!(t3, 2000)

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")
      assert has_element?(lv, "#team-tpn-out-of-order")
      assert has_element?(lv, "#team-tpn-out-of-order-#{t1.id}")
      assert has_element?(lv, "#team-tpn-out-of-order-regenerate")

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/teams?tpn=1")
      assert has_element?(lv, "#team-tpn")
      assert has_element?(lv, "#team-tpn-exchange-form-#{t2.id}")
      refute has_element?(lv, "#team-tpn-exchange-form-#{t1.id}")

      lv
      |> form("#team-tpn-exchange-form-#{t2.id}", %{"b" => to_string(t3.id)})
      |> render_submit()

      assert Repo.reload!(t2).pairing_number == 3
      assert Repo.reload!(t3).pairing_number == 2
      assert [_] = Audit.list_for_tournament(t.id, action: "team.numbers_changed")

      lv |> element("#team-tpn-regenerate") |> render_click()
      assert has_element?(lv, "#team-tpn-confirm")
      assert has_element?(lv, "#team-tpn-change-#{t1.id}")
      lv |> element("#team-tpn-confirm-yes") |> render_click()

      assert Repo.reload!(t1).pairing_number == 6
      assert Compliance.fide_mode?(Repo.reload!(t))
      assert [_, _] = Audit.list_for_tournament(t.id, action: "team.numbers_changed")
    end

    test "round 4 paired: nothing renumbers", %{conn: conn, scope: scope} do
      {t, _} = event(scope, 8)

      for round <- 1..4 do
        pair_next!(t)
        play!(t, round)
      end

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/teams")
      assert has_element?(lv, "#team-tpn-locked")
      refute has_element?(lv, "#team-tpn-open")
    end
  end

  describe "the printouts" do
    test "match sheets carry the IDs and the average fielded", %{conn: conn, scope: scope} do
      {t, _} = event(scope)
      pair_next!(t)

      [match | _] =
        t.id |> Tournaments.get_round(1) |> Map.fetch!(:id) |> Tournaments.list_matches()

      html = conn |> get(~p"/t/#{t.id}/print/team-match-sheets?round=1") |> html_response(200)
      assert html =~ "match-sheet-avg-#{match.id}"
      assert html =~ ~r/>ID</
    end

    test "the blank line-up forms: one per team, with the opponent and colours once paired", %{
      conn: conn,
      scope: scope
    } do
      {t, [t1 | _]} = event(scope)

      html = conn |> get(~p"/t/#{t.id}/print/team-lineup-forms") |> html_response(200)
      assert html =~ "lineup-form-#{t1.id}"
      assert html =~ "Reserves"

      pair_next!(t)

      html =
        conn
        |> get(~p"/t/#{t.id}/print/team-lineup-forms?round=1&team=#{t1.id}")
        |> html_response(200)

      assert html =~ "lineup-form-#{t1.id}"
      assert html =~ "White"
      refute html =~ "lineup-form-#{t1.id + 1}"

      assert conn |> get(~p"/t/#{t.id}/print/team-lineup-forms?round=1&team=0") |> response(404)
    end
  end

  describe "the Standings page" do
    test "shows each team's latest average fielded", %{conn: conn, scope: scope} do
      {t, [t1 | _]} = event(scope)
      pair_next!(t)
      play!(t, 1)

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/standings")
      assert has_element?(lv, "#team-avg-elo-head")
      assert has_element?(lv, "#team-avg-elo-#{t1.id}", ~r/\d{4}/)

      html = conn |> get(~p"/t/#{t.id}/print/team-standings") |> html_response(200)
      assert html =~ "Avg. Elo"
    end
  end
end
