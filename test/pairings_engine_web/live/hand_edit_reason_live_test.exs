defmodule PairingsEngineWeb.HandEditReasonLiveTest do
  @moduledoc """
  The optional reason for a hand edit and the time a round was paired: the
  box in the confirmation, the audit row, the Pairings page, the audit page
  and the ITDX file's OpenPairings block. The reason is never required.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PairingsEngine.{Audit, HandReason, Pairing, Repo, Tournaments, TrfExport}

  setup :register_and_log_in_user

  defp tournament(scope, names) do
    {:ok, t} =
      Tournaments.create_tournament(scope, %{
        "name" => "Hand edits",
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
      for {name, i} <- Enum.with_index(names) do
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
    {:ok, round} = Pairing.pair_next_round(Repo.reload!(t))
    Tournaments.get_round(t.id, round.number)
  end

  defp swap!(lv, a, b) do
    render_click(lv, "arm_swap", %{"player-id" => to_string(a.id)})
    render_click(lv, "pick_swap_target", %{"player-id" => to_string(b.id)})
  end

  defp swap_row(t),
    do:
      t.id |> Audit.list_for_tournament() |> Enum.find(&(&1.action == "pairing.players_swapped"))

  defp itdx(t) do
    {:ok, text} = TrfExport.export(Repo.reload!(t), nil, itdx: true)

    text
    |> String.split("\r\n")
    |> Enum.filter(&String.starts_with?(&1, "### OP "))
  end

  describe "a swap with a reason" do
    test "the reason is stored, shown, and written in the ITDX file", %{conn: conn, scope: scope} do
      {t, [_ann, _ben, cas, dan]} = tournament(scope, ~w(Ann Ben Cas Dan))
      pair!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

      swap!(lv, cas, dan)
      assert has_element?(lv, "#confirm-reason")

      lv
      |> form("#confirm-reason-form", %{"reason" => "Caf\u00E9 clash:\r\nsame club"})
      |> render_change()

      render_click(lv, "apply_confirm", %{})

      assert swap_row(t).details["reason"] == "Caf\u00E9 clash: same club"
      assert has_element?(lv, "#hand-edit-reasons", "Caf\u00E9 clash: same club")

      {:ok, audit, _} = live(conn, ~p"/t/#{t.id}/audit")
      assert render(audit) =~ "Reason given"

      event =
        Enum.find(itdx(t), &(&1 =~ "pairing.players_swapped"))

      assert event =~ ~s( reason "Cafe clash: same club")
      assert event =~ ~r/^### OP event \d{4}-\d\d-\d\d \d\d:\d\d UTC round 1: /
      assert event == String.replace(event, ~r/[^\x20-\x7E]/, "")
    end

    test "no reason: nothing stored, nothing in the way", %{conn: conn, scope: scope} do
      {t, [_ann, _ben, cas, dan]} = tournament(scope, ~w(Ann Ben Cas Dan))
      pair!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

      swap!(lv, cas, dan)
      refute has_element?(lv, "#confirm-reason[required]")
      render_click(lv, "apply_confirm", %{})

      refute Map.has_key?(swap_row(t).details, "reason")
      refute has_element?(lv, "#hand-edit-reasons")
      refute Enum.any?(itdx(t), &(&1 =~ " reason "))
    end

    test "a blank reason is no reason", %{conn: conn, scope: scope} do
      {t, [_ann, _ben, cas, dan]} = tournament(scope, ~w(Ann Ben Cas Dan))
      pair!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

      swap!(lv, cas, dan)
      lv |> form("#confirm-reason-form", %{"reason" => "   \t "}) |> render_change()
      render_click(lv, "apply_confirm", %{})

      refute Map.has_key?(swap_row(t).details, "reason")
    end
  end

  describe "finishing the hand edits" do
    test "the reason goes on the MPA row", %{conn: conn, scope: scope} do
      {t, [_ann, _ben, cas, dan]} = tournament(scope, ~w(Ann Ben Cas Dan))
      pair!(t)
      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")

      swap!(lv, cas, dan)
      render_click(lv, "apply_confirm", %{})
      lv |> element("#mpa-end") |> render_click()

      lv
      |> form("#mpa-end-reason-form", %{"reason" => "Players asked, same coach"})
      |> render_change()

      lv |> element("#mpa-ack") |> render_click()
      lv |> element("#mpa-end-confirm") |> render_click()

      row =
        t.id |> Audit.list_for_tournament() |> Enum.find(&(&1.action == "pairing.mpa_finished"))

      assert row.details["reason"] == "Players asked, same coach"
      assert Enum.any?(itdx(t), &(&1 =~ ~s(pairing.mpa_finished) and &1 =~ "same coach"))
    end
  end

  describe "when the round was paired" do
    test "the page shows it and the OP round line says it", %{conn: conn, scope: scope} do
      {t, _} = tournament(scope, ~w(Ann Ben Cas Dan))
      round = pair!(t)

      assert %DateTime{} = round.paired_at
      assert abs(DateTime.diff(DateTime.utc_now(), round.paired_at)) < 60

      {:ok, lv, _html} = live(conn, ~p"/t/#{t.id}/pairings")
      assert has_element?(lv, "#round-paired-at")

      line = Enum.find(itdx(t), &(&1 =~ ~r/^### OP round 1: /))
      assert line =~ ", paired #{Calendar.strftime(round.paired_at, "%Y-%m-%d %H:%M")} UTC"

      # The round's own time replaces the audit row's in the file.
      refute Enum.any?(itdx(t), &(&1 =~ "pairing.round_paired"))
    end

    test "pairing the round again after an unpair updates it", %{scope: scope} do
      {t, _} = tournament(scope, ~w(Ann Ben Cas Dan))
      first = pair!(t)

      Repo.update_all(
        from_round(first.id),
        set: [paired_at: ~U[2020-01-01 00:00:00Z]]
      )

      Pairing.delete_round(t.id, 1)
      again = pair!(t)

      assert DateTime.compare(again.paired_at, ~U[2021-01-01 00:00:00Z]) == :gt
    end

    test "the backfill takes the newest paired row of the audit trail", %{scope: scope} do
      {t, _} = tournament(scope, ~w(Ann Ben Cas Dan))
      round = pair!(t)
      Repo.update_all(from_round(round.id), set: [paired_at: nil])

      Audit.log(t.id, scope, "pairing.round_paired", %{round: 1})

      path =
        Path.expand(
          "../../../priv/repo/migrations/20261026115444_add_paired_at_to_rounds.exs",
          __DIR__
        )

      mod = PairingsEngine.Repo.Migrations.AddPairedAtToRounds
      unless Code.ensure_loaded?(mod), do: Code.require_file(path)

      Repo.query!(apply(mod, :backfill_sql, []))
      stamped = Tournaments.get_round(t.id, 1).paired_at
      assert %DateTime{} = stamped
      assert abs(DateTime.diff(DateTime.utc_now(), stamped)) < 120
    end
  end

  defp from_round(id) do
    import Ecto.Query
    from(r in PairingsEngine.Tournaments.Round, where: r.id == ^id)
  end

  describe "HandReason" do
    test "clean/1 strips control characters and line breaks and caps the length" do
      assert HandReason.clean("  a\u0000b\r\nc\td  ") == "a b c d"
      assert HandReason.clean("   ") == nil
      assert HandReason.clean(nil) == nil
      assert String.length(HandReason.clean(String.duplicate("x", 500))) == 200
    end

    test "ascii/1 is plain printable ASCII" do
      assert HandReason.ascii("Caf\u00E9 \u00D8st\u00E4 \u4E2D") == "Cafe sta"
      assert HandReason.ascii("a\nb") == "a b"
    end
  end
end
