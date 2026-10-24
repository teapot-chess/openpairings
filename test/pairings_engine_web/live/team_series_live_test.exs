defmodule PairingsEngineWeb.TeamSeriesLiveTest do
  @moduledoc """
  Board order chosen per round, the series and club of a team, and the
  individual ranking: the Options card, the Teams page, the match page, the
  Standings page and the print.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Repo, Tournaments}

  @moduletag :capture_log

  setup :register_and_log_in_user

  defp event(scope, attrs \\ []) do
    {t, [a, b]} =
      team_round_robin(
        [{"Alpha", [2100, 2000, 1900]}, {"Beta", [2050, 1950, 1850]}],
        [boards: 3, rounds_count: 1, user_id: scope.user.id] ++ attrs
      )

    {t, a, b}
  end

  describe "Board order on the Options page" do
    test "is saved before round 1", %{conn: conn, scope: scope} do
      {t, _, _} = event(scope)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/settings/options")
      assert has_element?(lv, "#team-settings-form #team-board-order")

      lv
      |> form("#team-settings-form", %{"tournament" => %{"team_board_order" => "free"}})
      |> render_submit()

      assert Repo.reload!(t).team_board_order == "free"
    end

    test "is locked in FIDE mode once round 1 is paired", %{conn: conn, scope: scope} do
      {t, _, _} = event(scope)
      pair_all!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/settings/options")
      assert has_element?(lv, "#team-board-order[disabled]")
    end
  end

  describe "the match page with a free board order" do
    test "says so and takes a line-up out of roster order", %{conn: conn, scope: scope} do
      {t, _, _} = event(scope, team_board_order: "free")
      t = pair_all!(t)
      {match, _} = match_between(t, 1, "Alpha", "Beta")

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings/1/matches/#{match.id}")
      assert has_element?(lv, "#lineups-free-order-hint")
      assert has_element?(lv, "#lineup-form")
    end

    test "keeps the roster order hint otherwise", %{conn: conn, scope: scope} do
      {t, _, _} = event(scope)
      t = pair_all!(t)
      {match, _} = match_between(t, 1, "Alpha", "Beta")

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings/1/matches/#{match.id}")
      refute has_element?(lv, "#lineups-free-order-hint")
    end
  end

  describe "the Teams page" do
    test "stores a series and a club and shows them on the card", %{conn: conn, scope: scope} do
      {t, a, _} = event(scope)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/teams")
      refute has_element?(lv, "#team-meta-#{a.id}")

      lv
      |> form("#edit-team-#{a.id}", %{
        "team" => %{"name" => "Alpha", "series" => "Reeks 1", "club" => "Schaakclub Alpha"}
      })
      |> render_submit()

      a = Repo.reload!(a)
      assert {a.series, a.club} == {"Reeks 1", "Schaakclub Alpha"}
      assert has_element?(lv, "#team-series-#{a.id}", "Reeks 1")
      assert has_element?(lv, "#team-club-#{a.id}", "Schaakclub Alpha")
    end

    test "a new team can be given a series and a club", %{conn: conn, scope: scope} do
      {t, _, _} = event(scope)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/teams")

      lv
      |> form("#create-team-form", %{
        "team" => %{"name" => "Gamma", "series" => "Reeks 2", "club" => "Gamma KSK"}
      })
      |> render_submit()

      gamma = t.id |> Tournaments.list_teams() |> Enum.find(&(&1.name == "Gamma"))
      assert {gamma.series, gamma.club} == {"Reeks 2", "Gamma KSK"}
    end
  end

  describe "the Standings page" do
    setup %{scope: scope} do
      {t, a, b} = event(scope)
      {:ok, _} = Tournaments.update_team(a, %{"series" => "Reeks 1"})
      {:ok, _} = Tournaments.update_team(b, %{"series" => "Reeks 2"})
      t = pair_all!(t)
      enter!(t, 1, "Alpha", "Beta", ["1-0", "1/2-1/2", "0-1"])
      %{t: t, a: a, b: b}
    end

    test "shows a series column when a team has one", %{conn: conn, t: t, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/standings")
      assert has_element?(lv, "#team-series-head")
      assert has_element?(lv, "#team-series-#{a.id}", "Reeks 1")
    end

    test "has no series column when no team has one", %{conn: conn, scope: scope} do
      {t, _, _} = event(scope)
      pair_all!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/standings")
      refute has_element?(lv, "#team-series-head")
    end

    test "the individual ranking is a view of its own, filtered by series", %{conn: conn, t: t} do
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/standings")
      refute has_element?(lv, "#player-ranking")

      lv |> element("#standings-view-players") |> render_click()
      assert has_element?(lv, "#player-ranking")
      assert has_element?(lv, "#player-ranking tbody tr", "Alpha 1")
      assert has_element?(lv, "#player-ranking tbody tr", "Beta 3")
      assert has_element?(lv, "#series-filter")

      lv |> form("#series-filter-form", %{"series" => "Reeks 2"}) |> render_change()
      assert_patch(lv, "/t/#{t.id}/standings?view=players&series=Reeks+2")
      assert has_element?(lv, "#player-ranking tbody tr", "Beta 3")
      refute has_element?(lv, "#player-ranking tbody tr", "Alpha 1")

      lv |> element("#standings-view-teams") |> render_click()
      assert has_element?(lv, "#team-standings")
      refute has_element?(lv, "#player-ranking")
    end

    test "the print lists the same players, with the series", %{conn: conn, t: t} do
      html = conn |> get(~p"/t/#{t.id}/print/player-ranking") |> html_response(200)
      assert html =~ "Alpha 1"
      assert html =~ "Beta 3"
      assert html =~ "Reeks 1"

      html = conn |> get(~p"/t/#{t.id}/print/player-ranking?series=Reeks+2") |> html_response(200)
      assert html =~ "Beta 3"
      refute html =~ "Alpha 1"
    end

    test "the team standings print carries the series", %{conn: conn, t: t} do
      html = conn |> get(~p"/t/#{t.id}/print/team-standings") |> html_response(200)
      assert html =~ "Reeks 1"
    end
  end
end
