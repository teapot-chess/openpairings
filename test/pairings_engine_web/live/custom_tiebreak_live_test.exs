defmodule PairingsEngineWeb.CustomTiebreakLiveTest do
  @moduledoc """
  The custom formula in the tie-break builder (Settings -> Tie-breaks) and
  on the Standings page.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PairingsEngine.{Pairing, Repo, Tournaments}
  alias PairingsEngine.Tiebreaks.Custom

  setup :register_and_log_in_user

  defp create_tournament(scope, attrs \\ %{}) do
    {:ok, t} =
      Tournaments.create_tournament(
        scope,
        Map.merge(%{"name" => "Custom", "type" => "swiss", "rounds_count" => "3"}, attrs)
      )

    t
  end

  defp open(conn, t) do
    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/settings/tiebreaks")
    lv |> element("#tb-family") |> render_change(%{"family" => "CUSTOM"})
    lv
  end

  defp save(lv), do: lv |> form("#tiebreaks-settings-form") |> render_submit()

  test "the builder offers it with its warning, the presets and their explanations", %{
    conn: conn,
    scope: scope
  } do
    t = create_tournament(scope)
    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/settings/tiebreaks")

    assert has_element?(lv, ~s(#tb-family option[value="CUSTOM"]))
    refute has_element?(lv, "#tb-custom")

    lv |> element("#tb-family") |> render_change(%{"family" => "CUSTOM"})

    assert has_element?(lv, "#tb-custom-warning", "Not a FIDE tie-break")

    for id <- ~w(forfeits_lost forfeits_won custom) do
      assert has_element?(lv, "#tb-custom-preset-#{id}")
      assert has_element?(lv, "#tb-custom-explanation-#{id}")
    end

    # The default: minus one forfeit loss, higher is better.
    assert has_element?(lv, ~s(#tb-custom-preset-forfeits_lost[aria-pressed="true"]))
    assert has_element?(lv, ~s(#tb-custom-sign-0-minus[aria-pressed="true"]))
    assert has_element?(lv, ~s(#tb-custom-figure-0 option[value="forfeit_losses"][selected]))
    assert has_element?(lv, ~s(#tb-custom-direction-higher[aria-pressed="true"]))
    assert has_element?(lv, "#tb-preview-code", "CUSTOM")
    refute has_element?(lv, "#tb-add[disabled]")
  end

  test "added and saved, the formula is stored with the list", %{conn: conn, scope: scope} do
    t = create_tournament(scope)
    lv = open(conn, t)

    lv |> element("#tb-add") |> render_click()
    assert has_element?(lv, "#tb-list-custom-formula", "Forfeit losses")
    assert has_element?(lv, "#tb-custom-in-list")
    save(lv)

    saved = Tournaments.get_tournament!(t.id)
    assert List.last(saved.tiebreaks) == "CUSTOM"
    assert saved.custom_tiebreak == Custom.default()
  end

  test "both ways: the reverse preset, signs, weights, figures and the direction", %{
    conn: conn,
    scope: scope
  } do
    t = create_tournament(scope)
    lv = open(conn, t)

    lv |> element("#tb-custom-preset-forfeits_won") |> render_click()
    assert has_element?(lv, ~s(#tb-custom-sign-0-plus[aria-pressed="true"]))
    assert has_element?(lv, ~s(#tb-custom-figure-0 option[value="forfeit_wins"][selected]))

    lv |> element("#tb-custom-add-term") |> render_click()
    lv |> element("#tb-custom-sign-1-plus") |> render_click()
    lv |> element("#tb-custom-weight-1") |> render_change(%{"cf_weight_1" => "0,5"})
    lv |> element("#tb-custom-figure-1") |> render_change(%{"cf_figure_1" => "black_wins"})
    lv |> element("#tb-custom-direction-lower") |> render_click()

    # Edited by hand, it is no longer the preset.
    assert has_element?(lv, ~s(#tb-custom-preset-custom[aria-pressed="true"]))
    assert has_element?(lv, "#tb-custom-formula", "lower is better")

    lv |> element("#tb-add") |> render_click()
    save(lv)

    assert %{
             "direction" => "lower",
             "terms" => [
               %{"figure" => "forfeit_wins", "sign" => "+", "weight" => 1.0},
               %{"figure" => "black_wins", "sign" => "+", "weight" => 0.5}
             ]
           } = Tournaments.get_tournament!(t.id).custom_tiebreak
  end

  test "an empty formula cannot be added", %{conn: conn, scope: scope} do
    t = create_tournament(scope)
    lv = open(conn, t)

    lv |> element("#tb-custom-remove-0") |> render_click()
    assert has_element?(lv, "#tb-add[disabled]")
    assert has_element?(lv, "#tb-add-reason", "at least one figure")

    lv |> element("#tb-custom-preset-custom") |> render_click()
    assert has_element?(lv, "#tb-add[disabled]")
  end

  test "above a FIDE tie-break it says it decides first", %{conn: conn, scope: scope} do
    t = create_tournament(scope)

    {:ok, _} =
      Tournaments.update_tournament(t, %{
        "tiebreaks" => ["BH", "CUSTOM"],
        "custom_tiebreak" => Custom.default()
      })

    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/settings/tiebreaks")
    assert has_element?(lv, "#tb-list-custom-not-fide")
    refute has_element?(lv, "#tb-custom-above-fide")

    lv |> element(~s(button[phx-click="tb_up"][phx-value-index="1"])) |> render_click()
    assert has_element?(lv, "#tb-custom-above-fide")
  end

  test "in FIDE mode, once round 1 is paired, the formula is locked with the list", %{
    conn: conn,
    scope: scope
  } do
    t = create_tournament(scope)

    {:ok, t} =
      Tournaments.update_tournament(t, %{
        "tiebreaks" => ["BH", "CUSTOM"],
        "custom_tiebreak" => Custom.default(),
        "round_dates" => ~w(2026-09-01 2026-09-08 2026-09-15)
      })

    for i <- 1..4 do
      {:ok, _} = Tournaments.create_player(t.id, %{"name" => "P#{i}", "fide_rating" => 2000 - i})
    end

    {:ok, _round} = Pairing.pair_next_round(Repo.reload!(t), [])

    lv = open(conn, t)
    assert has_element?(lv, "#tiebreak-editor[disabled]")
    assert has_element?(lv, "#tiebreaks-fide-lock")

    # A forged event cannot get past the save either.
    render_click(lv, "cf_direction", %{"direction" => "lower"})
    save(lv)
    assert Tournaments.get_tournament!(t.id).custom_tiebreak == Custom.default()
  end

  test "the standings show the column, the formula and each player's working", %{
    conn: conn,
    scope: scope
  } do
    t = create_tournament(scope)

    {:ok, t} =
      Tournaments.update_tournament(t, %{
        "tiebreaks" => ["CUSTOM"],
        "custom_tiebreak" => Custom.default(),
        "round_dates" => ~w(2026-09-01 2026-09-08 2026-09-15)
      })

    players =
      for i <- 1..4 do
        {:ok, p} =
          Tournaments.create_player(t.id, %{"name" => "P#{i}", "fide_rating" => 2000 - i})

        p
      end

    {:ok, round} = Pairing.pair_next_round(Repo.reload!(t), [])
    round = Tournaments.get_round(t.id, round.number)

    for p <- round.pairings,
        p.black_player_id,
        do: {:ok, _} = Tournaments.update_pairing_result(p, "1-0FF")

    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/standings")
    assert has_element?(lv, "#custom-tiebreak-header", "CUSTOM")
    assert has_element?(lv, "#custom-tiebreak-note", "Forfeit losses")

    for p <- players do
      assert has_element?(lv, ~s(#custom-tiebreak-#{p.id}[title*="Forfeit losses"]))
    end
  end
end
