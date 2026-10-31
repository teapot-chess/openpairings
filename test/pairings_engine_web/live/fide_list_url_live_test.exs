defmodule PairingsEngineWeb.FideListUrlLiveTest do
  @moduledoc """
  The rating-list download address on the Connections page: who sees it, what
  it accepts, how it ranks against `FIDE_LIST_URL`, and the Test button.

  Not async: the edition (`:local_mode`) and the `:fide` env are process-wide.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PairingsEngine.{Accounts, Audit, Meta}
  alias PairingsEngine.Fide.Sync

  @default "https://ratings.fide.com/download/players_list.zip"

  setup do
    previous_local = Application.get_env(:pairings_engine, :local_mode)
    previous_fide = Application.get_env(:pairings_engine, :fide)
    Application.put_env(:pairings_engine, :local_mode, false)
    Application.put_env(:pairings_engine, :fide, [])

    on_exit(fn ->
      restore(:local_mode, previous_local)
      restore(:fide, previous_fide)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:pairings_engine, key)
  defp restore(key, value), do: Application.put_env(:pairings_engine, key, value)

  defp as_role(%{conn: conn, user: user}, role) do
    {:ok, u} = Accounts.set_role(user.email, role)
    log_in_user(conn, u)
  end

  defp submit_url(lv, url) do
    lv |> form("#fide-source-form", list_url: %{url: url}) |> render_submit()
  end

  describe "precedence" do
    test "default, then environment, then the saved address" do
      assert Sync.list_url() == @default
      assert Sync.list_url_source() == :default

      Application.put_env(:pairings_engine, :fide, list_url: "https://env.example/list.zip")
      assert Sync.list_url() == "https://env.example/list.zip"
      assert Sync.list_url_source() == :env

      Sync.put_list_url("https://ui.example/list.zip")
      assert Sync.list_url() == "https://ui.example/list.zip"
      assert Sync.list_url_source() == :ui
      assert Sync.source_label() == "ui.example"

      Sync.put_list_url(nil)
      assert Sync.list_url() == "https://env.example/list.zip"
    end

    test "the saved address is what the freshness check asks" do
      Sync.put_list_url("https://ui.example/list.zip")
      test_pid = self()

      Req.Test.stub(PairingsEngine.Fide.FreshnessTest, fn conn ->
        send(test_pid, {:asked, conn.host})
        Plug.Conn.send_resp(conn, 200, "")
      end)

      PairingsEngine.Fide.Freshness.remote_modified()
      assert_receive {:asked, "ui.example"}
    end
  end

  describe "validation" do
    test "trims, strips quotes, and accepts only absolute https" do
      assert Sync.validate_list_url("  \"https://a.example/x.zip\"  ") ==
               {:ok, "https://a.example/x.zip"}

      assert Sync.validate_list_url("'https://a.example/x.zip'") ==
               {:ok, "https://a.example/x.zip"}

      assert Sync.validate_list_url("   ") == {:ok, nil}
      assert Sync.validate_list_url("http://a.example/x.zip") == {:error, :https_only}

      assert Sync.validate_list_url("http://a.example/x.zip", true) ==
               {:ok, "http://a.example/x.zip"}

      assert Sync.validate_list_url("ftp://a.example/x.zip", true) == {:error, :invalid}
      assert Sync.validate_list_url("not a url") == {:error, :invalid}
      assert Sync.validate_list_url("https://") == {:error, :invalid}
    end
  end

  describe "the control" do
    setup :register_and_log_in_user

    test "a plain account on a hosted server does not see it, and its events do nothing", ctx do
      {:ok, lv, _} = live(as_role(ctx, "support"), ~p"/fide")
      refute has_element?(lv, "#fide-source")

      render_hook(lv, "save_list_url", %{"list_url" => %{"url" => "https://evil.example/x.zip"}})
      render_hook(lv, "test_list_url", %{"url" => "https://evil.example/x.zip"})
      render_hook(lv, "clear_list_url", %{})

      assert Meta.get("fide_list_url") == nil
      assert Sync.list_url() == @default
    end

    test "an administrator saves, the page says where it comes from, and the audit log records it",
         ctx do
      conn = as_role(ctx, "admin")
      {:ok, lv, _} = live(conn, ~p"/fide")
      assert has_element?(lv, "#fide-source")
      assert render(lv) =~ "FIDE&#39;s own address"

      submit_url(lv, "  \"https://mirror.example/players_list.zip\" ")

      assert Sync.list_url() == "https://mirror.example/players_list.zip"
      assert has_element?(lv, "#fide-source-current", "Set here")
      assert has_element?(lv, "#fide-source-current", "https://mirror.example/players_list.zip")

      [row | _] = Audit.list_machine_wide(actions: ["fide.list_url_changed"])

      assert row.details["changed_fields"]["list_url"] ==
               [nil, "https://mirror.example/players_list.zip"]

      # Saving the same thing again is not an act.
      submit_url(lv, "https://mirror.example/players_list.zip")
      assert length(Audit.list_machine_wide(actions: ["fide.list_url_changed"])) == 1

      lv |> element("#fide-source-clear") |> render_click()
      assert Sync.list_url() == @default
      assert has_element?(lv, "#fide-source-current", "FIDE's own address")

      [newest | _] = Audit.list_machine_wide(actions: ["fide.list_url_changed"])

      assert newest.details["changed_fields"]["list_url"] ==
               ["https://mirror.example/players_list.zip", nil]
    end

    test "the environment value is named as such, and returns after Use default", ctx do
      Application.put_env(:pairings_engine, :fide, list_url: "https://env.example/list.zip")
      {:ok, lv, _} = live(as_role(ctx, "admin"), ~p"/fide")
      assert has_element?(lv, "#fide-source-current", "FIDE_LIST_URL")

      submit_url(lv, "https://ui.example/list.zip")
      lv |> element("#fide-source-clear") |> render_click()
      assert Sync.list_url() == "https://env.example/list.zip"
    end

    test "http is refused on a server and a nonsense address is refused anywhere", ctx do
      {:ok, lv, _} = live(as_role(ctx, "admin"), ~p"/fide")

      submit_url(lv, "http://mirror.example/x.zip")
      assert has_element?(lv, "#fide-source-error", "https://")
      assert Meta.get("fide_list_url") == nil

      submit_url(lv, "banana")
      assert has_element?(lv, "#fide-source-error")
      assert Meta.get("fide_list_url") == nil
    end

    test "on a desktop installation anybody may change it, and http is allowed", ctx do
      Application.put_env(:pairings_engine, :local_mode, true)
      {:ok, lv, _} = live(ctx.conn, ~p"/fide")
      assert has_element?(lv, "#fide-source")

      submit_url(lv, "http://192.168.1.5/players_list.zip")
      assert Sync.list_url() == "http://192.168.1.5/players_list.zip"
    end
  end

  describe "the Test button" do
    setup :register_and_log_in_user

    test "reports status, last-modified and size", ctx do
      Req.Test.stub(PairingsEngine.Fide.FreshnessTest, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("last-modified", "Thu, 01 Oct 2026 12:00:00 GMT")
        |> Plug.Conn.put_resp_header("content-length", "41000000")
        |> Plug.Conn.send_resp(200, "")
      end)

      {:ok, lv, _} = live(as_role(ctx, "admin"), ~p"/fide")
      lv |> element("#fide-source-test") |> render_click()

      assert has_element?(lv, "#fide-source-test-result", "200")
      assert has_element?(lv, "#fide-source-test-result", "Thu, 01 Oct 2026")
      assert has_element?(lv, "#fide-source-test-result", "41.0 MB")
      # Testing is not saving.
      assert Meta.get("fide_list_url") == nil
    end

    test "says plainly when the server refuses or cannot be reached", ctx do
      {:ok, lv, _} = live(as_role(ctx, "admin"), ~p"/fide")

      Req.Test.stub(PairingsEngine.Fide.FreshnessTest, fn conn ->
        Plug.Conn.send_resp(conn, 403, "")
      end)

      lv |> element("#fide-source-test") |> render_click()
      assert has_element?(lv, "#fide-source-test-result", "403")

      Req.Test.stub(PairingsEngine.Fide.FreshnessTest, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      lv |> element("#fide-source-test") |> render_click()
      assert has_element?(lv, "#fide-source-test-result", "refused")
    end
  end
end
