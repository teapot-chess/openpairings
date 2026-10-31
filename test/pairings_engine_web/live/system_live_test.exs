defmodule PairingsEngineWeb.SystemLiveTest do
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :capture_log

  alias PairingsEngine.Accounts
  alias PairingsEngine.Ops.{Age, ErrorReports, OffsiteBackup}

  setup :register_and_log_in_user

  describe "as an administrator" do
    setup %{conn: conn, user: user} do
      {:ok, admin} = Accounts.set_role(user.email, "admin")
      {:ok, conn: log_in_user(conn, admin)}
    end

    test "shows health, says off-site is not configured, and the empty error list", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/system")

      assert has_element?(lv, "#health-status")
      assert has_element?(lv, "#health-database")
      assert has_element?(lv, "#offsite-disabled")
      assert has_element?(lv, "#errors-empty")
      assert has_element?(lv, "#system-dashboard-link")
    end

    test "lists error reports and forgets them", %{conn: conn} do
      {:new, row} =
        ErrorReports.record(ErrorReports.from_crash({%RuntimeError{message: "kaput"}, []}))

      {:ok, lv, _html} = live(conn, ~p"/admin/system")
      assert has_element?(lv, "#error-#{row.id}", "kaput")

      lv |> element("#error-forget-#{row.id}") |> render_click()
      refute has_element?(lv, "#error-#{row.id}")
      assert ErrorReports.list() == []
    end

    test "send now pushes and lists the run", %{conn: conn} do
      {_, public} = Age.generate_identity()

      Application.put_env(:pairings_engine, :offsite_backup,
        recipients: [public],
        s3: [
          endpoint: "https://x.test",
          bucket: "b",
          access_key_id: "a",
          secret_access_key: "s",
          prefix: "op"
        ]
      )

      on_exit(fn ->
        Application.delete_env(:pairings_engine, :offsite_backup)
      end)

      Req.Test.stub(OffsiteBackup, &Plug.Conn.send_resp(&1, 200, ""))

      {:ok, lv, _html} = live(conn, ~p"/admin/system")
      assert has_element?(lv, "#offsite-send-now")

      # Whatever the test environment's backup directory holds, the attempt
      # is recorded, and the page shows it.
      lv |> element("#offsite-send-now") |> render_click()
      _ = render_async(lv)

      assert has_element?(lv, "#offsite-runs")
    end
  end

  test "an arbiter without the role is sent home", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/system")
  end

  test "LiveDashboard is for administrators only", %{conn: conn} do
    assert redirected_to(get(conn, "/admin/dashboard")) == "/"
  end

  test "LiveDashboard opens for an administrator", %{conn: conn, user: user} do
    {:ok, admin} = Accounts.set_role(user.email, "admin")
    conn = conn |> log_in_user(admin) |> get("/admin/dashboard/home")
    assert html_response(conn, 200) =~ "Dashboard"
  end
end
