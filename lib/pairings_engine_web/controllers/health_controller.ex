defmodule PairingsEngineWeb.HealthController do
  @moduledoc """
  `GET /healthz`: 200 and `"status": "ok"` when the database answers, 503 and
  `"degraded"` when it does not. See `PairingsEngine.Ops.Health` for what is
  in the body and why so little.

  Routed outside every pipeline: no session, no CSRF, no locale, no rate
  limit, no log line (`log: false` on the route and in
  `PairingsEngineWeb.Plugs.RequestLogging`). Never cached.
  """
  use PairingsEngineWeb, :controller

  alias PairingsEngine.Ops.Health

  def show(conn, _params), do: respond(conn, Health.report())

  @doc false
  # Split from show/2 so the 503 can be tested without breaking a database.
  def respond(conn, report) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(if report.status == "ok", do: 200, else: 503)
    |> json(report)
  end
end
