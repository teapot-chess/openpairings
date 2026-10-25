defmodule PairingsEngineWeb.SettingsTiebreakPickerTest do
  # async: false: sequential SQLite writes, like the other Settings LiveView tests.
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PairingsEngine.{Audit, Pairing, Repo, Standings, Tournaments}

  setup :register_and_log_in_user

  defp create_tournament(scope, type \\ "swiss") do
    {:ok, tournament} =
      Tournaments.create_tournament(scope, %{
        "name" => "Picker",
        "type" => type,
        "rounds_count" => "5"
      })

    tournament
  end

  defp family(lv, id), do: lv |> element("#tb-family") |> render_change(%{"family" => id})
  defp pick(lv, button_id), do: lv |> element("##{button_id}") |> render_click()
  defp add(lv), do: lv |> element("#tb-add") |> render_click()

  test "the builder offers base families only, in groups", %{conn: conn, scope: scope} do
    tournament = create_tournament(scope)
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    for id <- ~w(BH FB SB AOB PS KS DE ARO TPR RTNG WIN) do
      assert has_element?(lv, ~s(#tb-family optgroup option[value="#{id}"]))
    end

    # Modifiers are not families, and a team-only family is not offered here.
    for id <- ~w(BH/C1 BH/P SSSC EMMSB EDEBT MP) do
      refute has_element?(lv, ~s(#tb-family option[value="#{id}"]))
    end

    assert has_element?(lv, ~s(#tb-family optgroup[label="Rating-based"]))
    assert has_element?(lv, ~s(#tb-family optgroup[label="Buchholz"]))
  end

  test "only the modifiers a family accepts are shown", %{conn: conn, scope: scope} do
    tournament = create_tournament(scope)
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    family(lv, "BH")
    assert has_element?(lv, "#tb-cut")
    assert has_element?(lv, "#tb-forfeits")
    refute has_element?(lv, "#tb-limit")
    refute has_element?(lv, "#tb-factor")

    family(lv, "KS")
    assert has_element?(lv, "#tb-limit")
    refute has_element?(lv, "#tb-cut")
    refute has_element?(lv, "#tb-forfeits")

    family(lv, "WIN")
    refute has_element?(lv, "#tb-cut")
    refute has_element?(lv, "#tb-forfeits")
  end

  test "the preview shows the C.07 code and the name, and Add keeps the code", %{
    conn: conn,
    scope: scope
  } do
    tournament = create_tournament(scope)
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    family(lv, "BH")
    pick(lv, "tb-cut-c1")
    lv |> element("#tb-forfeits") |> render_click()

    assert has_element?(lv, "#tb-preview-code", "BH/C1/P")
    assert has_element?(lv, "#tb-preview-name", "forfeits counted")

    add(lv)
    assert has_element?(lv, "#tiebreak-editor", "forfeits counted")
    assert has_element?(lv, "#tb-add[disabled]")
    assert has_element?(lv, "#tb-add-reason")
  end

  test "a combination with an old spelling is stored under it", %{conn: conn, scope: scope} do
    tournament = create_tournament(scope)
    {:ok, _} = Tournaments.update_tournament(tournament, %{tiebreaks: []})
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    family(lv, "BH")
    pick(lv, "tb-cut-c1")
    assert has_element?(lv, "#tb-preview-code", "BH/C1")
    add(lv)

    pick(lv, "tb-cut-m1")
    add(lv)

    family(lv, "ARO")
    pick(lv, "tb-cut-c1")
    add(lv)

    lv |> form("#tiebreaks-settings-form") |> render_submit()
    assert Tournaments.get_tournament!(tournament.id).tiebreaks == ~w(BHC1 MBH AROC1)
  end

  # In a browser, LiveView sends a button's own `value` property under the key
  # "value" and it beats `phx-value-value`; a button with no value attribute
  # sends "", so every choice arrived as the first one. LiveViewTest does not
  # do that, which is how it got past the tests above. The attribute is the
  # only thing a test here can hold on to.
  test "the choice buttons do not carry their choice in phx-value-value",
       %{conn: conn, scope: scope} do
    tournament = create_tournament(scope, "team-swiss")
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    family(lv, "BH")
    assert has_element?(lv, ~s(#tb-cut-m2[phx-value-option="M2"]))
    assert has_element?(lv, ~s(#tb-ref-gp[phx-value-option="GP"]))
    refute has_element?(lv, "#tiebreak-builder [phx-value-value]")
  end

  test "a combination already in the list cannot be added", %{conn: conn, scope: scope} do
    tournament = create_tournament(scope)
    {:ok, _} = Tournaments.update_tournament(tournament, %{tiebreaks: ["BHC1"]})
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    family(lv, "BH")
    pick(lv, "tb-cut-c1")

    assert has_element?(lv, "#tb-add[disabled]")
    assert has_element?(lv, "#tb-add-reason")

    pick(lv, "tb-cut-c2")
    refute has_element?(lv, "#tb-add[disabled]")
  end

  test "a team tournament's builder takes the score basis and any SSSC factor", %{
    conn: conn,
    scope: scope
  } do
    tournament = create_tournament(scope, "team-swiss")
    {:ok, _} = Tournaments.update_tournament(tournament, %{tiebreaks: []})
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    for id <- ~w(SSSC EMMSB EDE PS MPVGP),
        do: assert(has_element?(lv, "#tb-family option[value=#{id}]"))

    family(lv, "BH")
    pick(lv, "tb-ref-gp")
    pick(lv, "tb-cut-c1")
    assert has_element?(lv, "#tb-preview-code", "BH:GP/C1")
    add(lv)

    family(lv, "SSSC")
    lv |> element("#tb-fore") |> render_click()
    lv |> element("#tb-factor") |> render_change(%{"factor" => "7"})
    assert has_element?(lv, "#tb-preview-code", "SSSC/F/K7")
    add(lv)

    lv |> form("#tiebreaks-settings-form") |> render_submit()
    assert Tournaments.get_tournament!(tournament.id).tiebreaks == ["BH:GP/C1", "SSSC/F/K7"]
  end

  test "a team builder pre-selects match points and keeps BH:MP as the old BH", %{
    conn: conn,
    scope: scope
  } do
    tournament = create_tournament(scope, "team-roundrobin")
    {:ok, _} = Tournaments.update_tournament(tournament, %{tiebreaks: []})
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    family(lv, "BH")
    assert has_element?(lv, "#tb-preview-code", "BH:MP")
    add(lv)
    lv |> form("#tiebreaks-settings-form") |> render_submit()
    assert Tournaments.get_tournament!(tournament.id).tiebreaks == ["BH"]
  end

  test "adding a tie-break from a group puts it in the list", %{conn: conn, scope: scope} do
    tournament = create_tournament(scope)
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    family(lv, "FB")
    pick(lv, "tb-cut-c1")
    add(lv)

    assert has_element?(lv, "#tiebreak-editor", "Fore Buchholz Cut-1")
  end

  test "the unrated rating and the shared place are saved with the tie-breaks", %{
    conn: conn,
    scope: scope
  } do
    tournament = create_tournament(scope)
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

    assert has_element?(lv, "#tiebreak-unrated-rating")
    refute has_element?(lv, "#shared-places[checked]")

    family(lv, "TPR")
    add(lv)

    lv
    |> form("#tiebreaks-settings-form", %{
      "tournament" => %{"tiebreak_unrated_rating" => "1300", "shared_places" => "true"}
    })
    |> render_submit()

    saved = Tournaments.get_tournament!(tournament.id)
    assert "TPR" in saved.tiebreaks
    assert saved.tiebreak_unrated_rating == 1300
    assert saved.shared_places == true
    assert Standings.dropped_tiebreaks(saved) == []

    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")
    assert has_element?(lv, "#shared-places[checked]")
    assert has_element?(lv, ~s(#tiebreak-unrated-rating[value="1300"]))
  end

  test "players level at the end show a shared place on the standings page", %{
    conn: conn,
    scope: scope
  } do
    tournament = create_tournament(scope)
    {:ok, _} = Tournaments.update_tournament(tournament, %{shared_places: true, tiebreaks: []})

    for name <- ~w(Alice Bob Carol) do
      {:ok, _} = Tournaments.create_player(tournament.id, %{"name" => name})
    end

    {:ok, _lv, html} = live(conn, ~p"/t/#{tournament.id}/standings")
    assert html =~ "1="
  end

  describe "the Tie-breaks page" do
    test "is in the rail, and the Tournament page no longer holds the editor", %{
      conn: conn,
      scope: scope
    } do
      tournament = create_tournament(scope)

      {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")
      assert has_element?(lv, "#settings-nav a[href='/t/#{tournament.id}/settings/tiebreaks']")
      assert has_element?(lv, "#tiebreaks-settings-form #tiebreak-editor")
      refute has_element?(lv, "#tiebreak-editor[disabled]")

      {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")
      refute has_element?(lv, "#tiebreak-editor")
      refute has_element?(lv, "#tiebreak-builder")
      refute has_element?(lv, "#tiebreak-unrated-rating")
      refute has_element?(lv, "#shared-places")
      assert has_element?(lv, "#tournament-settings-form")
    end

    test "moves, removes and presets are saved by the Save button, and audited", %{
      conn: conn,
      scope: scope
    } do
      tournament = create_tournament(scope)
      {:ok, _} = Tournaments.update_tournament(tournament, %{tiebreaks: ~w(BH SB PS)})
      {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

      lv |> element("button[phx-click=tb_down][phx-value-index='0']") |> render_click()
      lv |> element("button[phx-click=tb_remove][phx-value-code='PS']") |> render_click()

      # Nothing is written until Save.
      assert Tournaments.get_tournament!(tournament.id).tiebreaks == ~w(BH SB PS)

      lv |> form("#tiebreaks-settings-form") |> render_submit()
      assert Tournaments.get_tournament!(tournament.id).tiebreaks == ~w(SB BH)

      assert Enum.any?(
               Audit.list_for_tournament(tournament.id),
               &(&1.action == "tournament.settings_updated")
             )

      lv |> element("button[phx-click=tb_reset]") |> render_click()
      lv |> form("#tiebreaks-settings-form") |> render_submit()
      defaults = PairingsEngine.Tiebreaks.fide_defaults_for(tournament)
      assert Tournaments.get_tournament!(tournament.id).tiebreaks == defaults
    end

    test "a save here writes nothing else of the tournament", %{conn: conn, scope: scope} do
      tournament = create_tournament(scope)
      {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")

      render_submit(lv, "save", %{
        "tournament" => %{"name" => "Hijacked", "shared_places" => "true"}
      })

      saved = Tournaments.get_tournament!(tournament.id)
      assert saved.name == "Picker"
      assert saved.shared_places
    end

    test "FIDE mode locks the editor and the save once round 1 is paired", %{
      conn: conn,
      scope: scope
    } do
      tournament = create_tournament(scope)

      for {name, i} <- Enum.with_index(~w(Ann Ben Cas Dan)) do
        {:ok, _} =
          Tournaments.create_player(tournament.id, %{
            tournament_id: tournament.id,
            name: name,
            fide_rating: 2000 - 100 * i
          })
      end

      {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")
      refute has_element?(lv, "#tiebreak-editor[disabled]")
      before = Tournaments.get_tournament!(tournament.id).tiebreaks

      {:ok, _round} = Pairing.pair_next_round(Repo.reload!(tournament), [])

      {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings/tiebreaks")
      assert has_element?(lv, "#tiebreaks-fide-lock")
      assert has_element?(lv, "#tiebreak-editor[disabled]")

      # A crafted event cannot change the list either: it is not sent.
      render_click(lv, "tb_reset", %{})
      render_submit(lv, "save", %{"tournament" => %{"shared_places" => "true"}})
      assert Tournaments.get_tournament!(tournament.id).tiebreaks == before
    end
  end
end
