defmodule PairingsEngineWeb.SystemLive do
  @moduledoc """
  Admin > System: is it up, is the off-site copy current, and what has
  crashed. The three questions an operator asks before anything else, on one
  page, for administrators only (`live_session :administration`).

  Everything here is read from this server's own tables
  (`PairingsEngine.Ops`), and nothing on it is a secret: the bucket's
  address, never its keys; how many public keys a backup is encrypted to,
  never which.
  """
  use PairingsEngineWeb, :live_view

  alias PairingsEngine.Accounts
  alias PairingsEngine.Accounts.User
  alias PairingsEngine.Authz
  alias PairingsEngine.Ops.{ErrorReports, Health, OffsiteBackup}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: gettext("System"), sending: false) |> load()}
  end

  defp load(socket) do
    config = OffsiteBackup.config()

    assign(socket,
      health: Health.report(),
      offsite_enabled: OffsiteBackup.enabled?(config),
      offsite: offsite_summary(config),
      runs: OffsiteBackup.runs(10),
      errors: ErrorReports.list()
    )
  end

  defp offsite_summary(config) do
    s3 = config[:s3] || []

    %{
      host: s3[:endpoint] && URI.parse(s3[:endpoint]).host,
      bucket: s3[:bucket],
      prefix: s3[:prefix],
      recipients: length(config[:recipients] || []),
      stale_hours: OffsiteBackup.stale_hours(config)
    }
  end

  @impl true
  def handle_event(event, params, socket) do
    if still_admin?(socket) do
      event(event, params, socket)
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("This page is for administrators."))
       |> redirect(to: ~p"/")}
    end
  end

  defp event("refresh", _params, socket), do: {:noreply, load(socket)}

  defp event("send-now", _params, socket) do
    {:noreply,
     socket
     |> assign(sending: true)
     |> start_async(:send, fn -> OffsiteBackup.push(force: true) end)}
  end

  defp event("forget", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id), do: ErrorReports.delete(id)
    {:noreply, load(socket)}
  end

  defp event("forget-all", _params, socket) do
    ErrorReports.clear()
    {:noreply, socket |> put_flash(:info, gettext("Error reports cleared.")) |> load()}
  end

  @impl true
  def handle_async(:send, result, socket) do
    flash =
      case result do
        {:ok, {:ok, _key}} -> {:info, gettext("Backup sent off-site.")}
        {:ok, :disabled} -> {:error, gettext("Off-site backups are not configured.")}
        _ -> {:error, gettext("The off-site backup failed; the run below says why.")}
      end

    {:noreply,
     socket |> assign(sending: false) |> put_flash(elem(flash, 0), elem(flash, 1)) |> load()}
  end

  defp still_admin?(socket) do
    case socket.assigns.current_scope do
      %{user: %User{id: id}} -> id |> Accounts.get_user() |> Authz.may_administer?()
      _ -> false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      publish_status={assigns[:publish_status]}
      update_notice={assigns[:update_notice]}
      fide_notice={assigns[:fide_notice]}
      flash={@flash}
      current_scope={@current_scope}
      current_path={assigns[:current_path]}
      active="admin"
    >
      <p class="hint"><.link navigate={~p"/admin"}>{gettext("Admin")}</.link></p>
      <h1>{gettext("System")}</h1>

      <div class="set-card" id="system-health">
        <h2>{gettext("Health")}</h2>
        <p class="hint">
          {gettext(
            "The same answer /healthz gives a monitor. Only the database decides whether it answers 200 or 503; the backup is reported beside it."
          )}
        </p>
        <dl class="system-facts">
          <dt>{gettext("Status")}</dt>
          <dd><.state id="health-status" value={@health.status} /></dd>
          <dt>{gettext("Database")}</dt>
          <dd><.state id="health-database" value={@health.checks.database} /></dd>
          <dt>{gettext("Off-site backup")}</dt>
          <dd><.state id="health-backup" value={@health.checks.backup} /></dd>
          <dt>{gettext("Version")}</dt>
          <dd id="health-version">{@health.version}</dd>
        </dl>
        <div class="actions">
          <button id="system-refresh" type="button" class="pe-btn" phx-click="refresh">
            {gettext("Check again")}
          </button>
          <.link id="system-dashboard-link" href={~p"/admin/dashboard"} class="pe-btn">
            {gettext("Open LiveDashboard")}
          </.link>
        </div>
      </div>

      <div class="set-card" id="system-offsite">
        <h2>{gettext("Off-site backup")}</h2>
        <%= if @offsite_enabled do %>
          <p class="hint">
            {gettext(
              "The newest local backup is encrypted to %{count} public key(s) and sent to %{bucket} on %{host}. This server cannot decrypt what it sends.",
              count: @offsite.recipients,
              bucket: @offsite.bucket,
              host: @offsite.host
            )}
            {gettext("Stale after %{hours} hours without a successful send.",
              hours: @offsite.stale_hours
            )}
          </p>
          <div class="actions">
            <button
              id="offsite-send-now"
              type="button"
              class="pe-btn primary"
              phx-click="send-now"
              disabled={@sending}
            >
              {if @sending, do: gettext("Sending..."), else: gettext("Send the newest backup now")}
            </button>
          </div>
        <% else %>
          <p class="hint" id="offsite-disabled">
            {gettext(
              "Not configured. Backups stay on this machine only. The OFFSITE_BACKUP_* settings in the deployment guide switch it on."
            )}
          </p>
        <% end %>

        <div :if={@runs != []} class="card-table-wrap">
          <table class="pe-table" id="offsite-runs">
            <thead>
              <tr>
                <th>{gettext("When")}</th>
                <th>{gettext("Result")}</th>
                <th>{gettext("Object")}</th>
                <th class="num">{gettext("Size")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={run <- @runs} id={"offsite-run-#{run.id}"}>
                <td>{format_time(run.finished_at)}</td>
                <td>
                  <.state value={if run.status == "ok", do: "ok", else: "failing"} />
                  <span :if={run.error} class="hint">{run.error}</span>
                </td>
                <td><code>{run.object_key}</code></td>
                <td class="num">{run.bytes && format_size(run.bytes)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div class="set-card" id="system-errors">
        <h2>{gettext("Errors")}</h2>
        <p class="hint">
          {gettext(
            "Crashes this server has logged, one row per kind, newest first. Kept here, not sent anywhere. Messages are cut short and stack traces carry no arguments, so no player data ends up on this page."
          )}
        </p>

        <p :if={@errors == []} id="errors-empty" class="hint">{gettext("Nothing has crashed.")}</p>

        <div :if={@errors != []}>
          <div class="actions">
            <button
              id="errors-forget-all"
              type="button"
              class="pe-btn"
              phx-click="forget-all"
              data-confirm={gettext("Forget every error report?")}
            >
              {gettext("Forget all")}
            </button>
          </div>

          <div :for={error <- @errors} id={"error-#{error.id}"} class="system-error">
            <div class="system-error-head">
              <strong>{error.kind}</strong>
              <span class="badge muted">{ngettext("once", "%{count} times", error.count)}</span>
              <button
                type="button"
                class="pe-btn"
                phx-click="forget"
                phx-value-id={error.id}
                id={"error-forget-#{error.id}"}
              >
                {gettext("Forget")}
              </button>
            </div>
            <p class="system-error-message">{error.message}</p>
            <p class="hint">
              {error.location} &middot; {gettext("first %{first}, last %{last}",
                first: format_time(error.first_seen_at),
                last: format_time(error.last_seen_at)
              )}
            </p>
            <details :if={error.stacktrace != ""}>
              <summary>{gettext("Stack trace")}</summary>
              <pre class="system-error-stack">{error.stacktrace}</pre>
            </details>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :value, :string, required: true
  attr :id, :string, default: nil

  defp state(assigns) do
    ~H"""
    <span id={@id} class={["badge", state_class(@value)]}>{state_label(@value)}</span>
    """
  end

  defp state_class(value) when value in ["ok"], do: "done"
  defp state_class("disabled"), do: "muted"
  defp state_class(_), do: "system-bad"

  defp state_label("ok"), do: gettext("OK")
  defp state_label("degraded"), do: gettext("Degraded")
  defp state_label("unreachable"), do: gettext("Unreachable")
  defp state_label("stale"), do: gettext("Stale")
  defp state_label("failing"), do: gettext("Failing")
  defp state_label("disabled"), do: gettext("Not configured")
  defp state_label(other), do: other

  defp format_time(nil), do: ""
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp format_size(bytes) when bytes >= 1_000_000, do: "#{Float.round(bytes / 1_000_000, 1)} MB"
  defp format_size(bytes), do: "#{max(div(bytes, 1_000), 1)} kB"
end
