defmodule PairingsEngineWeb.PlayersImportLiveTest do
  @moduledoc """
  "Import players" on the Players page: upload -> review -> confirm.
  """
  use PairingsEngineWeb.ConnCase

  import Phoenix.LiveViewTest

  alias PairingsEngine.{Audit, Tournaments}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    {:ok, tournament} =
      Tournaments.create_tournament(scope, %{
        "name" => "Import Test",
        "type" => "swiss",
        "rounds_count" => "5",
        "round_dates" => List.duplicate("2026-07-15", 5),
        "tiebreaks" => ["BH", "SB"],
        "chief_arbiter" => "Jane Arbiter",
        "federation" => "BEL",
        "rate_of_play" => "90 min + 30 sec/move"
      })

    {:ok, _} =
      Tournaments.create_player(tournament.id, %{
        "name" => "Claes, Bram",
        "fide_id" => "201001",
        "fide_rating" => "2000"
      })

    %{tournament: tournament}
  end

  defp upload(lv, name, content) do
    lv
    |> file_input("#player-import-form", :player_import, [
      %{name: name, content: content, type: "application/octet-stream"}
    ])
    |> render_upload(name)
  end

  defp trf_line(rank, name, fide) do
    "001 " <>
      String.pad_leading("#{rank}", 4) <>
      "  " <>
      "   " <>
      " " <>
      String.pad_trailing(name, 33) <>
      " " <>
      String.pad_leading("1500", 4) <>
      " " <>
      "BEL" <>
      " " <>
      String.pad_leading("#{fide}", 11) <>
      " " <>
      String.pad_trailing("1990-01-01", 10) <>
      " 0.0  " <> String.pad_leading("#{rank}", 4)
  end

  test "a CSV is reviewed, then added in one go", %{conn: conn, tournament: t, scope: scope} do
    {:ok, lv, html} = live(conn, ~p"/t/#{t.id}/players")
    assert html =~ "import-players-button"
    refute has_element?(lv, "#player-import-form")

    lv |> element("#import-players-button") |> render_click()
    assert has_element?(lv, "#player-import-form")
    refute has_element?(lv, "#confirm-player-import")

    csv = """
    name;rating;fide_id
    New One;1500;
    Somebody;1600;201001
    ;1700;
    New Two;1400;
    """

    upload(lv, "players.csv", csv)

    assert has_element?(lv, "#player-import-review")
    assert has_element?(lv, "#player-import-add #player-import-row-2")
    assert has_element?(lv, "#player-import-add #player-import-row-5")
    refute has_element?(lv, "#player-import-add #player-import-row-3")
    assert has_element?(lv, "#player-import-duplicates #player-import-duplicate-3")
    assert has_element?(lv, "#player-import-invalid #player-import-invalid-4")
    assert has_element?(lv, "#confirm-player-import")

    # Nothing is written before the confirm.
    assert length(Tournaments.list_players(t.id)) == 1

    lv |> element("#confirm-player-import") |> render_click()

    refute has_element?(lv, "#player-import-form")
    names = t.id |> Tournaments.list_players() |> Enum.map(& &1.name) |> Enum.sort()
    assert names == ["Claes, Bram", "New One", "New Two"]

    assert Enum.any?(Audit.list_for_tournament(t.id), fn e ->
             e.action == "player.imported" and e.details["count"] == 2 and
               e.details["source"] == "csv"
           end)

    assert scope
  end

  test "a TRF is read for its players only", %{conn: conn, tournament: t} do
    {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/players")
    lv |> element("#import-players-button") |> render_click()

    trf = Enum.join(["012 Whatever", trf_line(1, "Peeters, Eva", 300_001)], "\r\n") <> "\r\n"
    upload(lv, "export.trf", trf)

    assert has_element?(lv, "#player-import-add #player-import-row-2")
    lv |> element("#confirm-player-import") |> render_click()

    assert [%{name: "Peeters, Eva", fide_id: 300_001}] =
             t.id |> Tournaments.list_players() |> Enum.filter(&(&1.fide_id == 300_001))
  end

  test "a file with nothing usable shows an error and no confirm button", %{
    conn: conn,
    tournament: t
  } do
    {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/players")
    lv |> element("#import-players-button") |> render_click()
    upload(lv, "bad.csv", "rating,fed\n1500,BEL\n")

    assert has_element?(lv, "#player-import-error")
    refute has_element?(lv, "#confirm-player-import")
  end

  test "cancel closes the panel and writes nothing", %{conn: conn, tournament: t} do
    {:ok, lv, _} = live(conn, ~p"/t/#{t.id}/players")
    lv |> element("#import-players-button") |> render_click()
    upload(lv, "p.csv", "name\nSomeone\n")
    assert has_element?(lv, "#confirm-player-import")

    lv |> element("#cancel-player-import") |> render_click()
    refute has_element?(lv, "#player-import-form")
    assert length(Tournaments.list_players(t.id)) == 1
  end

  test "the audit page words the entry", %{tournament: t, scope: scope} do
    Audit.log(t.id, scope, "player.imported", %{"count" => 3, "source" => "trf"})
    entry = Enum.find(Audit.list_for_tournament(t.id), &(&1.action == "player.imported"))
    assert PairingsEngineWeb.AuditLive.describe(entry) =~ "3 players from a TRF file"
  end
end
