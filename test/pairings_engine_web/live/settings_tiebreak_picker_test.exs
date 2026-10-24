defmodule PairingsEngineWeb.SettingsTiebreakPickerTest do
  # async: false: sequential SQLite writes, like the other Settings LiveView tests.
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PairingsEngine.{Standings, Tournaments}

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
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")

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
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")

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
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")

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
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")

    family(lv, "BH")
    pick(lv, "tb-cut-c1")
    assert has_element?(lv, "#tb-preview-code", "BH/C1")
    add(lv)

    pick(lv, "tb-cut-m1")
    add(lv)

    family(lv, "ARO")
    pick(lv, "tb-cut-c1")
    add(lv)

    lv |> form("#tournament-settings-form") |> render_submit()
    assert Tournaments.get_tournament!(tournament.id).tiebreaks == ~w(BHC1 MBH AROC1)
  end

  test "a combination already in the list cannot be added", %{conn: conn, scope: scope} do
    tournament = create_tournament(scope)
    {:ok, _} = Tournaments.update_tournament(tournament, %{tiebreaks: ["BHC1"]})
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")

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
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")

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

    lv |> form("#tournament-settings-form") |> render_submit()
    assert Tournaments.get_tournament!(tournament.id).tiebreaks == ["BH:GP/C1", "SSSC/F/K7"]
  end

  test "a team builder pre-selects match points and keeps BH:MP as the old BH", %{
    conn: conn,
    scope: scope
  } do
    tournament = create_tournament(scope, "team-roundrobin")
    {:ok, _} = Tournaments.update_tournament(tournament, %{tiebreaks: []})
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")

    family(lv, "BH")
    assert has_element?(lv, "#tb-preview-code", "BH:MP")
    add(lv)
    lv |> form("#tournament-settings-form") |> render_submit()
    assert Tournaments.get_tournament!(tournament.id).tiebreaks == ["BH"]
  end

  test "adding a tie-break from a group puts it in the list", %{conn: conn, scope: scope} do
    tournament = create_tournament(scope)
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")

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
    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")

    assert has_element?(lv, "#tiebreak-unrated-rating")
    refute has_element?(lv, "#shared-places[checked]")

    family(lv, "TPR")
    add(lv)

    lv
    |> form("#tournament-settings-form", %{
      "tournament" => %{"tiebreak_unrated_rating" => "1300", "shared_places" => "true"}
    })
    |> render_submit()

    saved = Tournaments.get_tournament!(tournament.id)
    assert "TPR" in saved.tiebreaks
    assert saved.tiebreak_unrated_rating == 1300
    assert saved.shared_places == true
    assert Standings.dropped_tiebreaks(saved) == []

    {:ok, lv, _html} = live(conn, ~p"/t/#{tournament.id}/settings")
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
end
