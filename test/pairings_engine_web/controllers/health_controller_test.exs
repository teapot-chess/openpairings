defmodule PairingsEngineWeb.HealthControllerTest do
  use PairingsEngineWeb.ConnCase, async: false

  test "GET /healthz answers 200 with a status, the version and one word per check", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert %{
             "status" => "ok",
             "version" => version,
             "checks" => %{"database" => "ok", "backup" => "disabled"}
           } = json_response(conn, 200)

    assert version == to_string(Application.spec(:pairings_engine, :vsn))
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    # No session: nothing was fetched, so nothing was set.
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "the body says nothing else", %{conn: conn} do
    body = conn |> get(~p"/healthz") |> json_response(200)
    assert Map.keys(body) |> Enum.sort() == ["checks", "status", "version"]
    assert Map.keys(body["checks"]) |> Enum.sort() == ["backup", "database"]
  end

  test "a stale off-site backup is reported and does not fail the check", %{conn: conn} do
    {_, public} = PairingsEngine.Ops.Age.generate_identity()

    Application.put_env(:pairings_engine, :offsite_backup,
      recipients: [public],
      s3: [endpoint: "https://x.test", bucket: "b", access_key_id: "a", secret_access_key: "s"]
    )

    on_exit(fn -> Application.delete_env(:pairings_engine, :offsite_backup) end)

    assert %{"status" => "ok", "checks" => %{"backup" => "stale"}} =
             conn |> get(~p"/healthz") |> json_response(200)
  end

  test "503 and degraded when the database does not answer", %{conn: conn} do
    report = %{
      status: "degraded",
      version: "x",
      checks: %{database: "unreachable", backup: "disabled"}
    }

    conn = PairingsEngineWeb.HealthController.respond(conn, report)

    assert %{"status" => "degraded", "checks" => %{"database" => "unreachable"}} =
             json_response(conn, 503)
  end
end
