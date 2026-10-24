defmodule PairingsEngineWeb.TeamOptionsLiveTest do
  @moduledoc """
  The three team-Swiss options on their pages: the primary score on
  Settings - Scoring, the team-number limit on Settings - Options (behind the
  leave-FIDE-mode gate when it is later than FIDE's), and the order drawn by
  lot on the Teams page.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Audit, Compliance, Repo}

  @moduletag :capture_log

  setup :register_and_log_in_user

  defp event(scope, attrs \\ []) do
    teams = for i <- 1..4, do: {"T#{i}", [2100 - i * 10, 2000 - i * 10]}

    {t, _} =
      team_swiss(
        teams,
        [boards: 2, rounds: 5, user_id: scope.user.id, round_dates: ~w(a b c d e)] ++ attrs
      )

    t
  end

  defp pass_both(lv) do
    assert has_element?(lv, "#fide-gate-warn")
    lv |> element("#fide-gate-continue") |> render_click()
    assert has_element?(lv, "#fide-gate-consequences")
    lv |> element("#fide-gate-confirm") |> render_click()
  end

  describe "the primary score (Settings - Scoring)" do
    test "saves game points without asking to leave FIDE mode", %{conn: conn, scope: scope} do
      t = event(scope)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/scoring")

      assert has_element?(lv, "#team-primary-score option[value='match_points'][selected]")

      render_submit(lv, "save", %{"tournament" => %{"team_primary_score" => "game_points"}})

      refute has_element?(lv, "#fide-gate")
      t = Repo.reload!(t)
      assert t.team_primary_score == "game_points"
      assert Compliance.fide_mode?(t)
      assert has_element?(lv, "#team-primary-score option[value='game_points'][selected]")
    end

    test "is disabled once round 1 is paired in FIDE mode", %{conn: conn, scope: scope} do
      t = event(scope)
      pair_next!(t)

      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/scoring")
      assert has_element?(lv, "#team-primary-score[disabled]")
      assert has_element?(lv, "#match-points-fide-lock")
    end

    test "the standings show the primary score in bold, named in the header",
         %{conn: conn, scope: scope} do
      t = event(scope, team_primary_score: "game_points")
      pair_next!(t)

      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/standings")
      assert lv |> element("#team-primary-head") |> render() =~ "GP"
    end
  end

  describe "the team-number limit (Settings - Options)" do
    test "a later round than FIDE's asks twice, then leaves FIDE mode",
         %{conn: conn, scope: scope} do
      t = event(scope)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/options")
      assert has_element?(lv, "#team-tpn-until-round[value='4']")

      params = %{"section" => "teams", "tournament" => %{"team_tpn_until_round" => "6"}}

      render_submit(lv, "save", params)
      assert has_element?(lv, "#fide-gate-reasons")
      lv |> element("#fide-gate-cancel") |> render_click()
      assert Repo.reload!(t).team_tpn_until_round == 4

      render_submit(lv, "save", params)
      pass_both(lv)

      t = Repo.reload!(t)
      assert t.team_tpn_until_round == 6
      refute Compliance.fide_mode?(t)

      assert [%{details: %{"setting" => "team_tpn_until_round"}}] =
               Audit.list_for_tournament(t.id, action: "tournament.fide_compliance_lost")
    end

    test "an earlier round saves straight away", %{conn: conn, scope: scope} do
      t = event(scope)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/options")

      render_submit(lv, "save", %{
        "section" => "teams",
        "tournament" => %{"team_tpn_until_round" => "3"}
      })

      refute has_element?(lv, "#fide-gate")
      assert Repo.reload!(t).team_tpn_until_round == 3
      assert Compliance.fide_mode?(Repo.reload!(t))
    end

    test "is not offered for a team round robin", %{conn: conn, scope: scope} do
      {t, _} =
        team_round_robin([{"A", [2000, 1900]}, {"B", [1950, 1850]}], user_id: scope.user.id)

      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/options")
      refute has_element?(lv, "#team-tpn-until-round")
    end
  end

  describe "the order drawn by lot (Teams page)" do
    test "offered only when the team rating is typed in", %{conn: conn, scope: scope} do
      t = event(scope)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/teams")
      refute has_element?(lv, "#team-draw-lot")
      assert has_element?(lv, "#team-draw-unavailable")

      manual = event(scope, team_rating_method: "manual", name: "Typed")
      {:ok, lv, _} = live(conn, ~p"/t/#{manual.id}/teams")
      assert has_element?(lv, "#team-draw-lot")
      refute has_element?(lv, "#team-draw-unavailable")
    end

    test "an order set by hand is asked about before it is replaced, and the draw is recorded",
         %{conn: conn, scope: scope} do
      # The fixture's teams count as ordered by hand.
      t = event(scope, team_rating_method: "manual")
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/teams")

      lv |> element("#team-draw-lot") |> render_click()
      assert has_element?(lv, "#team-draw-confirm")
      lv |> element("#team-draw-confirm-no") |> render_click()
      refute has_element?(lv, "#team-draw-confirm")
      assert Repo.reload!(t).teams_drawn_at == nil

      lv |> element("#team-draw-lot") |> render_click()
      lv |> element("#team-draw-confirm-yes") |> render_click()

      assert %DateTime{} = Repo.reload!(t).teams_drawn_at
      assert has_element?(lv, "#team-drawn-note")

      assert [%{details: %{"drawn_by_lot" => true, "order" => order}}] =
               Audit.list_for_tournament(t.id, action: "team.seeding_changed")

      assert Enum.sort(order) == ~w(T1 T2 T3 T4)
    end

    test "no order set by hand draws without asking", %{conn: conn, scope: scope} do
      t = event(scope, team_rating_method: "manual", teams_ordered_by_hand: false)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/teams")

      lv |> element("#team-draw-lot") |> render_click()
      refute has_element?(lv, "#team-draw-confirm")
      assert %DateTime{} = Repo.reload!(t).teams_drawn_at
    end

    test "gone once round 1 is paired; the record stays", %{conn: conn, scope: scope} do
      t = event(scope, team_rating_method: "manual", teams_ordered_by_hand: false)
      {:ok, _} = PairingsEngine.Tournaments.draw_team_order(t)
      pair_next!(t)

      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/teams")
      refute has_element?(lv, "#team-draw-lot")
      assert has_element?(lv, "#team-drawn-note")
    end
  end
end
