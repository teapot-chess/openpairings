defmodule PairingsEngineWeb.SettingsSeriesTest do
  use PairingsEngineWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias PairingsEngine.{Repo, TournamentSeries, Tournaments}
  alias PairingsEngine.Tournaments.Tournament

  setup :register_and_log_in_user

  defp tournament(scope, name, start_date) do
    {:ok, t} =
      Tournaments.create_tournament(scope, %{
        "name" => name,
        "type" => "swiss",
        "rounds_count" => "5"
      })

    # Derived from the round dates in real life; set straight here.
    Repo.update_all(from(x in Tournament, where: x.id == ^t.id), set: [start_date: start_date])
    %{t | start_date: start_date}
  end

  defp series_id(t), do: Tournaments.get_tournament!(t.id).series_id

  setup %{scope: scope} do
    %{
      e25: tournament(scope, "Open Brugge", "2025-03-01"),
      e26: tournament(scope, "Open Brugge II", "2026-03-01")
    }
  end

  test "the card offers the choices and joining links both editions", %{
    conn: conn,
    e25: e25,
    e26: e26
  } do
    {:ok, lv, _html} = live(conn, ~p"/t/#{e26.id}/settings/results")

    assert has_element?(lv, "#series-card")
    assert has_element?(lv, "#series-form")
    assert has_element?(lv, "#series-choice option[value=none][selected]")
    assert has_element?(lv, "#series-choice option[value=new]")
    assert has_element?(lv, "#series-choice option[value='join:#{e25.id}']", "2025")
    refute has_element?(lv, "#series-editions")

    lv
    |> form("#series-form", series: %{choice: "join:#{e25.id}"})
    |> render_submit()

    assert series_id(e26)
    assert series_id(e26) == series_id(e25)
    assert has_element?(lv, "#series-editions #series-edition-#{e25.id}")
    assert has_element?(lv, "#series-choice option[value='join:#{e25.id}'][selected]")
  end

  test "choosing not to be in a series leaves it", %{conn: conn, scope: scope, e25: e25} do
    {:ok, _} = TournamentSeries.start_series(scope, e25)
    {:ok, lv, _html} = live(conn, ~p"/t/#{e25.id}/settings/results")

    assert has_element?(lv, "#series-choice option[value=keep][selected]")

    lv |> form("#series-form", series: %{choice: "none"}) |> render_submit()
    assert series_id(e25) == nil
  end

  test "a read-only tournament cannot be changed", %{conn: conn, e25: e25} do
    Repo.update_all(
      from(t in Tournament, where: t.id == ^e25.id),
      set: [archived_at: DateTime.truncate(DateTime.utc_now(), :second)]
    )

    {:ok, lv, _html} = live(conn, ~p"/t/#{e25.id}/settings/results")
    assert has_element?(lv, "#series-choice[disabled]")
    assert has_element?(lv, "#series-save[disabled]")
  end
end
