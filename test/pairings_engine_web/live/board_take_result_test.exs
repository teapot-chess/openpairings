defmodule PairingsEngineWeb.BoardTakeResultTest do
  @moduledoc """
  Taking what a live board saw: the per-board "Take" button and "Take all
  agreeing". Both enter through the ordinary result path; neither ever
  happens without a click.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PairingsEngine.BoardLinkFixtures

  alias PairingsEngine.{Audit, BoardLink, Repo, Tournaments}
  alias PairingsEngine.Tournaments.Pairing

  setup :register_and_log_in_user

  setup %{scope: scope} do
    fixture = paired_tournament(scope)
    {:ok, link, _secret} = BoardLink.create_link(scope, fixture.tournament)
    Map.put(fixture, :link, link)
  end

  defp finished(link, t, board, result, extra \\ %{}) do
    {:ok, _} =
      BoardLink.report(
        link,
        t,
        report_for(board, Map.merge(%{"status" => "finished", "result" => result}, extra))
      )
  end

  defp entries(t),
    do: Audit.list_for_tournament(t.id, action: "pairing.result_entered")

  test "Take enters exactly the board's result and the audit log says where from", %{
    conn: conn,
    link: link,
    tournament: t,
    boards: [board1 | _]
  } do
    finished(link, t, board1, "0-1")
    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

    assert has_element?(lv, "#take-board-result-#{board1.id}")
    lv |> element("#take-board-result-#{board1.id}") |> render_click()

    assert Repo.get!(Pairing, board1.id).result == "0-1"
    refute has_element?(lv, "#take-board-result-#{board1.id}")
    assert has_element?(lv, "#board-report-#{board1.id}.match")

    [entry] = entries(t)
    assert entry.details["source"] == "board"
    assert entry.details["to"] == "0-1"
  end

  test "a result typed by hand carries no board source", %{
    conn: conn,
    tournament: t,
    boards: [board1 | _]
  } do
    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

    lv
    |> form("#result-form-#{board1.id}", %{"result" => "1-0"})
    |> render_change()

    [entry] = entries(t)
    refute Map.has_key?(entry.details, "source")
  end

  test "no Take where a result is entered, the game is live, or the board's moves were not seen",
       %{conn: conn, link: link, tournament: t, boards: [board1, board2]} do
    finished(link, t, board1, "1-0", %{"guessed" => 1})
    {:ok, _} = Tournaments.update_pairing_result(board2, "1/2-1/2")
    finished(link, t, board2, "1-0")

    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

    refute has_element?(lv, "#take-board-result-#{board1.id}")
    refute has_element?(lv, "#take-board-result-#{board2.id}")
    refute has_element?(lv, "#take-board-results")
  end

  test "reconstructed and rewritten moves are not trusted either", %{
    link: link,
    tournament: t,
    boards: [board1, board2]
  } do
    finished(link, t, board1, "1-0", %{"reconstructed" => 2})
    finished(link, t, board2, "1-0", %{"rewritten" => 1})

    reports = BoardLink.summaries(t.id)
    assert BoardLink.takeable(board1, reports[board1.game_uid]) == :error
    assert BoardLink.takeable(board2, reports[board2.game_uid]) == :error
  end

  test "a game still in progress offers nothing", %{
    conn: conn,
    link: link,
    tournament: t,
    boards: [board1 | _]
  } do
    {:ok, _} = BoardLink.report(link, t, report_for(board1))
    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")
    refute has_element?(lv, "#take-board-result-#{board1.id}")
    refute has_element?(lv, "#take-all-board-results")
  end

  test "Take all agreeing asks with the count, skips existing and untrusted, never auto-enters",
       %{
         conn: conn,
         link: link,
         tournament: t,
         boards: [board1, board2]
       } do
    # One trustworthy board with no result; one with a result already entered.
    finished(link, t, board1, "1-0")
    {:ok, _} = Tournaments.update_pairing_result(board2, "0-1")
    finished(link, t, board2, "1-0")

    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

    # Seeing the page enters nothing.
    assert Repo.get!(Pairing, board1.id).result == ""
    assert has_element?(lv, "#take-all-board-results", "(1)")

    lv |> element("#take-all-board-results") |> render_click()
    assert has_element?(lv, "#take-all-board-results-text")
    assert Repo.get!(Pairing, board1.id).result == ""

    # Cancel enters nothing.
    lv |> element("#take-all-board-results-cancel") |> render_click()
    assert Repo.get!(Pairing, board1.id).result == ""

    lv |> element("#take-all-board-results") |> render_click()
    lv |> element("#take-all-board-results-yes") |> render_click()

    assert Repo.get!(Pairing, board1.id).result == "1-0"
    # The existing result, which differs from the board, is untouched.
    assert Repo.get!(Pairing, board2.id).result == "0-1"
    refute has_element?(lv, "#take-board-results")

    [entry] = entries(t)
    assert entry.details["source"] == "board"
    assert entry.details["bulk"] == true
  end

  test "Take all counts only trustworthy boards", %{
    conn: conn,
    link: link,
    tournament: t,
    boards: [board1, board2]
  } do
    finished(link, t, board1, "1/2-1/2")
    finished(link, t, board2, "1-0", %{"guessed" => 3})

    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")
    assert has_element?(lv, "#take-all-board-results", "(1)")

    lv |> element("#take-all-board-results") |> render_click()
    lv |> element("#take-all-board-results-yes") |> render_click()

    assert Repo.get!(Pairing, board1.id).result == "1/2-1/2"
    assert Repo.get!(Pairing, board2.id).result == ""
  end

  test "an archived tournament refuses both, and writes nothing", %{
    conn: conn,
    link: link,
    tournament: t,
    boards: [board1 | _]
  } do
    finished(link, t, board1, "1-0")

    t
    |> Ecto.Changeset.change(archived_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update!()

    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")
    assert has_element?(lv, "#take-board-result-#{board1.id}[disabled]")

    html = render_hook(lv, "take_board_result", %{"pairing-id" => to_string(board1.id)})
    assert html =~ "flash"
    assert Repo.get!(Pairing, board1.id).result == ""
    assert entries(t) == []

    render_hook(lv, "take_all_board_results", %{})
    assert Repo.get!(Pairing, board1.id).result == ""
  end

  test "a stale Take for a board that has a result since does not overwrite", %{
    conn: conn,
    link: link,
    tournament: t,
    boards: [board1 | _]
  } do
    finished(link, t, board1, "1-0")
    {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")
    {:ok, _} = Tournaments.update_pairing_result(board1, "0-1")

    render_hook(lv, "take_board_result", %{"pairing-id" => to_string(board1.id)})
    assert Repo.get!(Pairing, board1.id).result == "0-1"
  end
end
