defmodule PairingsEngineWeb.PlayerCardMenusLiveTest do
  @moduledoc """
  The Players Card from the right-click menus: the seat menu on the Pairings
  page and the row menu on the Standings page open the same card the Players
  list does.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PairingsEngine.{Pairing, Repo, Tournaments}

  setup :register_and_log_in_user

  defp tournament(scope) do
    {:ok, t} =
      Tournaments.create_tournament(scope, %{
        "name" => "Card menus",
        "type" => "swiss",
        "start_date" => "2026-07-15",
        "rounds_count" => "3",
        "round_dates" => List.duplicate("2026-07-15", 3),
        "tiebreaks" => ["BH", "SB"],
        "chief_arbiter" => "Jane Arbiter",
        "federation" => "BEL",
        "rate_of_play" => "90 min + 30 sec/move"
      })

    players =
      for {name, i} <- Enum.with_index(~w(Ann Ben Cas Dan)) do
        {:ok, p} =
          Tournaments.create_player(t.id, %{
            tournament_id: t.id,
            name: name,
            fide_rating: 2000 - 50 * i
          })

        p
      end

    {Repo.reload!(t), players}
  end

  defp pair!(t) do
    {:ok, _round} = Pairing.pair_next_round(Repo.reload!(t))
  end

  describe "the Pairings page seat menu" do
    test "offers the card third and opens the same card", %{conn: conn, scope: scope} do
      {t, [ann | _]} = tournament(scope)
      pair!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

      render_click(lv, "open_menu", %{
        "x" => 10,
        "y" => 10,
        "scope" => "seated",
        "player-id" => to_string(ann.id)
      })

      assert has_element?(lv, "#hand-edit-menu [role=menuitem]:nth-child(3)#menu-players-card")

      lv |> element("#menu-players-card") |> render_click()

      assert has_element?(lv, "#player-card-dialog")
      refute has_element?(lv, "#hand-edit-menu")

      render_click(lv, "card_next", %{})
      assert has_element?(lv, "#player-card-dialog")

      render_click(lv, "close_card", %{})
      refute has_element?(lv, "#player-card-dialog")
    end

    test "a payload that is not a number opens no card", %{conn: conn, scope: scope} do
      {t, _players} = tournament(scope)
      pair!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

      render_click(lv, "show_card", %{"player-id" => "nope"})
      refute has_element?(lv, "#player-card-dialog")
    end
  end

  describe "the Standings page row menu" do
    test "a player's row opens the menu and the card", %{conn: conn, scope: scope} do
      {t, [ann | _]} = tournament(scope)
      pair!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/standings")

      assert has_element?(lv, "#standing-row-#{ann.id}[data-scope=standing]")
      assert has_element?(lv, "#standing-name-#{ann.id}[data-seat][role=button]")

      render_click(lv, "open_menu", %{
        "x" => 10,
        "y" => 10,
        "scope" => "standing",
        "player-id" => to_string(ann.id),
        "keyboard" => true
      })

      assert has_element?(lv, "#standings-player-menu #menu-players-card")
      assert has_element?(lv, "#standings-player-menu #menu-edit-player")

      lv |> element("#menu-players-card") |> render_click()

      assert has_element?(lv, "#player-card-dialog")
      refute has_element?(lv, "#standings-player-menu")

      render_click(lv, "card_prev", %{})
      assert has_element?(lv, "#player-card-dialog")

      render_click(lv, "close_card", %{})
      refute has_element?(lv, "#player-card-dialog")
    end

    test "a bad menu payload opens nothing", %{conn: conn, scope: scope} do
      {t, _players} = tournament(scope)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/standings")

      render_click(lv, "open_menu", %{"scope" => "standing", "player-id" => "x"})
      render_click(lv, "open_menu", %{"scope" => "seated", "player-id" => "1"})
      render_click(lv, "show_card", %{"player-id" => "x"})
      refute has_element?(lv, "#standings-player-menu")
      refute has_element?(lv, "#player-card-dialog")
    end

    test "Edit player goes to the Players page with that player's form", %{
      conn: conn,
      scope: scope
    } do
      {t, [ann | _]} = tournament(scope)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/standings")

      render_click(lv, "open_menu", %{
        "x" => 1,
        "y" => 1,
        "scope" => "standing",
        "player-id" => to_string(ann.id)
      })

      lv |> element("#menu-edit-player") |> render_click()
      assert_redirect(lv, ~p"/t/#{t.id}/players?edit=#{ann.id}")
    end

    test "a garbage player id goes nowhere", %{conn: conn, scope: scope} do
      {t, _players} = tournament(scope)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/standings")
      render_click(lv, "edit_player", %{"player-id" => "x"})
      render_click(lv, "edit_player", %{})
      refute has_element?(lv, "#standings-player-menu")
    end
  end

  describe "the Players page ?edit= link" do
    test "opens that player's edit dialog", %{conn: conn, scope: scope} do
      {t, [ann | _]} = tournament(scope)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/players?edit=#{ann.id}")

      assert has_element?(lv, "#player-edit-form")
    end

    test "ignores a foreign or junk id", %{conn: conn, scope: scope} do
      {t, _players} = tournament(scope)
      {other, [stranger | _]} = tournament(scope)
      assert other.id != t.id

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/players?edit=#{stranger.id}")
      refute has_element?(lv, "#player-edit-form")

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/players?edit=junk")
      refute has_element?(lv, "#player-edit-form")
    end
  end
end
