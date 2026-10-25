defmodule PairingsEngineWeb.TeamEntryUxLiveTest do
  @moduledoc """
  Team events from the player side: the Team select on the add and edit
  forms, the Team column of the players list and its printout, and the
  club that the "teams of the same club" rule needs (a notice with inline
  inputs on the Restrictions page, suggestions from the players' clubs).
  """
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PairingsEngine.TeamFixtures

  alias PairingsEngine.{Audit, TeamClubs, Tournaments}

  @moduletag :capture_log

  setup :register_and_log_in_user

  defp event(scope, teams \\ [{"Rooks", [2100, 2000]}, {"Bishops", [2050, 1950]}]) do
    {t, created} =
      team_swiss(teams,
        user_id: scope.user.id,
        rounds: 3,
        start_date: "2026-07-15",
        round_dates: ["2026-07-15", "2026-07-16", "2026-07-17"],
        chief_arbiter: "Jane Arbiter",
        federation: "BEL",
        rate_of_play: "90 min + 30 sec/move"
      )

    {t, created}
  end

  defp rule!(t, kind) do
    {:ok, rule} = Tournaments.add_pairing_rule(t, %{"kind" => kind})
    rule
  end

  defp player(t, name, attrs \\ %{}) do
    {:ok, p} = Tournaments.create_player(t.id, Map.merge(%{"name" => name}, attrs))
    p
  end

  defp named(t, name), do: t.id |> Tournaments.list_players() |> Enum.find(&(&1.name == name))

  describe "the Team select when entering a player" do
    test "puts the new player at the bottom of the chosen team", %{conn: conn, scope: scope} do
      {t, [rooks, _]} = event(scope)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/players")
      render_click(lv, "add", %{})

      assert has_element?(lv, "#add-player-team")

      lv
      |> form("#add-player-form", %{
        "player" => %{"name" => "Newcomer", "sex" => "m", "team_id" => to_string(rooks.id)}
      })
      |> render_submit()

      p = named(t, "Newcomer")
      assert p.team_id == rooks.id
      assert p.board_order == 3
      assert Enum.any?(Audit.list_for_tournament(t.id), &(&1.action == "team.player_assigned"))
    end

    test "no team leaves the player without one, and an individual event has no select", %{
      conn: conn,
      scope: scope
    } do
      {t, _} = event(scope)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/players")
      render_click(lv, "add", %{})

      lv
      |> form("#add-player-form", %{"player" => %{"name" => "Free", "sex" => "m"}})
      |> render_submit()

      assert named(t, "Free").team_id == nil

      {:ok, swiss} =
        Tournaments.create_tournament(scope, %{
          "name" => "Open",
          "type" => "swiss",
          "rounds_count" => "3",
          "round_dates" => List.duplicate("2026-07-15", 3),
          "tiebreaks" => ["BH"],
          "chief_arbiter" => "Jane Arbiter",
          "federation" => "BEL",
          "rate_of_play" => "90 min + 30 sec/move"
        })

      {:ok, lv, _} = live(conn, ~p"/t/#{swiss.id}/players")
      render_click(lv, "add", %{})
      refute has_element?(lv, "#add-player-team")
    end

    test "a team of another tournament is refused and nothing is put on it", %{
      conn: conn,
      scope: scope
    } do
      {t, _} = event(scope)
      {_other, [foreign, _]} = event(scope)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/players")
      render_click(lv, "add", %{})

      lv
      |> form("#add-player-form", %{"player" => %{"name" => "Sneaky", "sex" => "m"}})
      |> render_submit(%{"player" => %{"team_id" => to_string(foreign.id)}})

      assert named(t, "Sneaky").team_id == nil
    end

    test "the registration dialog moves a player to another team", %{conn: conn, scope: scope} do
      {t, [rooks, bishops]} = event(scope)
      p = named(t, "Rooks 1")
      assert p.team_id == rooks.id

      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/players")
      render_click(lv, "edit_player", %{"id" => to_string(p.id)})
      assert has_element?(lv, "#edit-player-team")

      lv
      |> form("#player-edit-form", %{"player" => %{"team_id" => to_string(bishops.id)}})
      |> render_submit()

      moved = Tournaments.get_player(t.id, p.id)
      assert moved.team_id == bishops.id
      assert moved.board_order == 3
      assert Tournaments.team_roster(t.id, rooks.id) |> Enum.map(& &1.board_order) == [1]

      # And back to no team.
      render_click(lv, "edit_player", %{"id" => to_string(p.id)})

      lv
      |> form("#player-edit-form", %{"player" => %{"team_id" => ""}})
      |> render_submit()

      assert Tournaments.get_player(t.id, p.id).team_id == nil
      assert Enum.any?(Audit.list_for_tournament(t.id), &(&1.action == "team.player_removed"))
    end
  end

  describe "the team in the players list" do
    test "shows team and board, and sorts by them", %{conn: conn, scope: scope} do
      {t, _} = event(scope)
      player(t, "Loner")
      {:ok, lv, html} = live(conn, ~p"/t/#{t.id}/players")

      cell = ~r/<td[^>]*data-col="team"[^>]*>\s*(.*?)\s*<\/td>/s
      cells = Regex.scan(cell, html) |> Enum.map(fn [_, c] -> String.trim(c) end)
      assert "Rooks · 1" in cells
      assert "Bishops · 2" in cells
      assert "-" in cells

      html = render_click(lv, "sort", %{"key" => "team"})
      cells = Regex.scan(cell, html) |> Enum.map(fn [_, c] -> String.trim(c) end)
      assert cells == ["Bishops · 1", "Bishops · 2", "Rooks · 1", "Rooks · 2", "-"]
    end

    test "is not a column of an individual event", %{conn: conn, scope: scope} do
      {:ok, swiss} = Tournaments.create_tournament(scope, %{"name" => "Open", "type" => "swiss"})
      player(swiss, "Solo")
      {:ok, _lv, html} = live(conn, ~p"/t/#{swiss.id}/players")
      refute html =~ ~s(data-col="team")
    end

    test "the printed list has a Team column by default in a team event only", %{
      conn: conn,
      scope: scope
    } do
      {t, _} = event(scope)
      html = get(conn, ~p"/t/#{t.id}/print/players") |> html_response(200)
      assert html =~ "<th>Team</th>"
      assert html =~ "Rooks · 1"

      {:ok, swiss} = Tournaments.create_tournament(scope, %{"name" => "Open", "type" => "swiss"})
      plain = get(conn, ~p"/t/#{swiss.id}/print/players?cols=team") |> html_response(200)
      refute plain =~ "<th>Team</th>"
    end
  end

  describe "TeamClubs.suggest/1" do
    defp ps(clubs), do: Enum.map(clubs, &%PairingsEngine.Tournaments.Player{club: &1})

    test "needs two players with a club and three quarters of them on one" do
      assert TeamClubs.suggest(ps(["Gistel", "Gistel", " gistel", "GISTEL", "Brugge"])) ==
               "Gistel"

      assert TeamClubs.suggest(ps(["Gistel", "Brugge"])) == nil
      assert TeamClubs.suggest(ps(["Gistel", "", nil])) == nil
      assert TeamClubs.suggest(ps(["Gistel", "Gistel", "Brugge"])) == nil
      assert TeamClubs.suggest(ps([])) == nil
    end
  end

  describe "teams without a club, on the Restrictions page" do
    test "no notice without a rule", %{conn: conn, scope: scope} do
      {t, _} = event(scope)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/restrictions")
      refute has_element?(lv, "#team-club-missing")
    end

    test "lists the clubless teams with an input each, and saves a club", %{
      conn: conn,
      scope: scope
    } do
      {t, [rooks, bishops]} = event(scope)
      {:ok, _} = Tournaments.update_team(bishops, %{"club" => "Gistel"})
      rule!(t, "team_club")

      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/restrictions")
      assert has_element?(lv, "#team-club-missing")
      assert has_element?(lv, "#team-club-form-#{rooks.id}")
      refute has_element?(lv, "#team-club-form-#{bishops.id}")

      lv
      |> form("#team-club-form-#{rooks.id}", %{"club" => "  Brugge "})
      |> render_submit()

      assert Enum.find(Tournaments.list_teams(t.id), &(&1.id == rooks.id)).club == "Brugge"
      refute has_element?(lv, "#team-club-missing")
      assert Enum.any?(Audit.list_for_tournament(t.id), &(&1.action == "team.updated"))
    end

    test "offers the players' club, and only applies it on the click", %{
      conn: conn,
      scope: scope
    } do
      {t, [rooks, _]} = event(scope)

      for p <- Tournaments.team_roster(t.id, rooks.id),
          do: {:ok, _} = Tournaments.update_player(p, %{"club" => "KSK Gistel"})

      rule!(t, "team_club")

      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/restrictions")
      assert has_element?(lv, "#team-club-suggest-#{rooks.id}", "KSK Gistel")
      assert Enum.find(Tournaments.list_teams(t.id), &(&1.id == rooks.id)).club == ""

      lv |> element("#team-club-suggest-#{rooks.id}") |> render_click()
      assert Enum.find(Tournaments.list_teams(t.id), &(&1.id == rooks.id)).club == "KSK Gistel"
    end

    test "a rule that names clubs does not need the others to have one", %{
      conn: conn,
      scope: scope
    } do
      {t, _} = event(scope)
      {:ok, _} = Tournaments.add_pairing_rule(t, %{"kind" => "team_club", "names" => ["Gistel"]})
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/restrictions")
      refute has_element?(lv, "#team-club-missing")
    end
  end

  describe "the Teams page and the club rule" do
    test "says the club is needed, and offers the suggestion", %{conn: conn, scope: scope} do
      {t, [rooks, bishops]} = event(scope)
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/teams")
      refute has_element?(lv, "#create-team-club-needed")

      for p <- Tournaments.team_roster(t.id, rooks.id),
          do: {:ok, _} = Tournaments.update_player(p, %{"club" => "KSK Gistel"})

      rule!(t, "team_club")
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/teams")
      assert has_element?(lv, "#create-team-club-needed")
      assert has_element?(lv, "#team-club-needed-#{bishops.id}")
      assert has_element?(lv, "#team-club-suggest-#{rooks.id}")
      refute has_element?(lv, "#team-club-suggest-#{bishops.id}")

      lv |> element("#team-club-suggest-#{rooks.id}") |> render_click()
      assert Enum.find(Tournaments.list_teams(t.id), &(&1.id == rooks.id)).club == "KSK Gistel"
    end
  end

  describe "players without a club, and the same-club rule" do
    setup %{scope: scope} do
      {:ok, t} =
        Tournaments.create_tournament(scope, %{
          "name" => "Open",
          "type" => "swiss",
          "rounds_count" => "3",
          "round_dates" => List.duplicate("2026-07-15", 3),
          "tiebreaks" => ["BH"],
          "chief_arbiter" => "Jane Arbiter",
          "federation" => "BEL",
          "rate_of_play" => "90 min + 30 sec/move"
        })

      player(t, "A", %{"club" => "Gistel"})
      player(t, "B")
      player(t, "C", %{"club" => "  "})
      %{t: t}
    end

    test "counts them and links to the list filtered to no club", %{conn: conn, t: t} do
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/restrictions")
      refute has_element?(lv, "#player-club-missing")

      {:ok, _} = Tournaments.add_pairing_rule(t, %{"kind" => "club"})
      {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/settings/restrictions")
      assert has_element?(lv, "#player-club-missing", "2 players have no club")
      assert has_element?(lv, ~s(#player-club-missing-link[href="/t/#{t.id}/players?club=none"]))

      {:ok, plist, html} = live(conn, ~p"/t/#{t.id}/players?club=none")
      assert has_element?(plist, "#players-club-filter")
      assert html =~ "B"
      refute html =~ ~s(data-player-id="#{named(t, "A").id}")

      plist |> element("#clear-club-filter") |> render_click()
      refute has_element?(plist, "#players-club-filter")
      assert render(plist) =~ ~s(data-player-id="#{named(t, "A").id}")
    end
  end
end
