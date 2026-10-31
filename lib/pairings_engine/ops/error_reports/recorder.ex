defmodule PairingsEngine.Ops.ErrorReports.Recorder do
  @moduledoc """
  The one process that writes crash reports, so the crashing ones never do.

  Two guards, both against the same failure - the thing that records crashes
  becoming the crash:

    * `ErrorReports.record/2` rescues everything, so a locked or missing
      database is a lost report, not a restart. A recorder that crashed on a
      bad database would log a crash, which it would be asked to record, on
      the same bad database.
    * the mailbox is capped: when a hundred reports are already waiting (a
      crash loop somewhere), further ones are dropped until it drains. The
      count on the row will be low; the page will still show the row.

  ## The e-mail

  When `OPS_ALERT_EMAIL` is set and SMTP is configured, a NEW fingerprint
  sends one short message to that address - which crash, where, and a link
  to the admin page, nothing else. At most one per `#{15}` minutes: a deploy
  that breaks ten pages is one e-mail and a page with ten rows, not an inbox
  full of the same news.
  """
  use GenServer

  import Swoosh.Email

  alias PairingsEngine.Ops.ErrorReports

  require Logger

  @mail_gap_ms :timer.minutes(15)
  @max_queue 100

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Hands a sanitized report over. Never blocks, never raises."
  def capture(server \\ __MODULE__, report) do
    case GenServer.whereis(server) do
      nil ->
        :ok

      pid ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, n} when n < @max_queue -> GenServer.cast(pid, {:capture, report})
          _ -> :ok
        end
    end
  end

  @impl true
  def init(opts) do
    {:ok, %{last_mail_at: nil, alert_email: Keyword.get_lazy(opts, :alert_email, &alert_email/0)}}
  end

  @impl true
  def handle_cast({:capture, report}, state) do
    state =
      case ErrorReports.record(report) do
        {:new, row} -> maybe_mail(row, state)
        _ -> state
      end

    {:noreply, state}
  end

  defp maybe_mail(_row, %{alert_email: nil} = state), do: state

  defp maybe_mail(row, state) do
    now = System.monotonic_time(:millisecond)

    if state.last_mail_at && now - state.last_mail_at < @mail_gap_ms do
      state
    else
      send_mail(state.alert_email, row)
      %{state | last_mail_at: now}
    end
  end

  defp send_mail(to, row) do
    email =
      new()
      |> to(to)
      |> from(PairingsEngine.Mailer.from())
      |> subject("OpenPairings: new error (#{row.kind})")
      |> text_body("""
      A crash this server had not seen before.

      #{row.kind}: #{row.message}
      at #{row.location || "?"}
      fingerprint #{row.fingerprint}

      Details, and every other one: #{admin_url()}

      At most one of these is sent every 15 minutes; the page has the rest.
      """)

    case PairingsEngine.Mailer.deliver(email) do
      {:ok, _} -> :ok
      # No crash_reason here, so this does not come back as a report.
      {:error, _} -> Logger.warning("Error report e-mail could not be sent")
    end
  rescue
    _ -> :ok
  end

  defp admin_url do
    PairingsEngineWeb.Endpoint.url() <> "/admin/system"
  rescue
    _ -> "/admin/system"
  end

  defp alert_email, do: Application.get_env(:pairings_engine, :ops_alert_email)
end
