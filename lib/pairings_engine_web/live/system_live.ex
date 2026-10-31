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
  alias PairingsEngine.Accounts.{SignupPolicy, User}
  alias PairingsEngine.Authz
  alias PairingsEngine.Ops.{ErrorReports, Health, OffsiteBackup}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: gettext("System"), sending: false) |> load()}
  end

  defp load(socket) do
    config = OffsiteBackup.config()

    socket
    |> assign(
      health: Health.report(),
      offsite_enabled: OffsiteBackup.enabled?(config),
      offsite: offsite_summary(config),
      runs: OffsiteBackup.runs(10),
      errors: ErrorReports.list()
    )
    |> load_signup()
  end

  # Who may create an account - see `PairingsEngine.Accounts.SignupPolicy`.
  defp load_signup(socket) do
    mode = SignupPolicy.mode()
    domains = Enum.join(SignupPolicy.domains(), ", ")

    assign(socket,
      signup_mode: mode,
      signup_domains: domains,
      signup_source: SignupPolicy.source(),
      signup_env_mode: SignupPolicy.env_mode(),
      signup_error: nil,
      signup_form: to_form(%{"mode" => mode, "domains" => domains}, as: :signup),
      invite_form: to_form(%{"email" => ""}, as: :invite),
      account_form: to_form(%{"email" => ""}, as: :account),
      invitations: Accounts.list_signup_invitations()
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

  defp event("save-signup", %{"signup" => params}, socket) do
    scope = socket.assigns.current_scope

    case Accounts.update_signup_policy(scope, params["mode"], params["domains"] || "") do
      :ok ->
        {:noreply, socket |> load_signup() |> put_flash(:info, gettext("Sign-up setting saved."))}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           signup_error: signup_error(reason),
           signup_form: to_form(params, as: :signup)
         )}
    end
  end

  defp event("clear-signup", _params, socket) do
    case Accounts.update_signup_policy(socket.assigns.current_scope, nil) do
      :ok ->
        {:noreply,
         socket
         |> load_signup()
         |> put_flash(
           :info,
           gettext("The saved sign-up setting is gone; the server's own applies.")
         )}

      {:error, reason} ->
        {:noreply, assign(socket, signup_error: signup_error(reason))}
    end
  end

  defp event("invite-user", %{"invite" => %{"email" => email}}, socket) do
    url_fun = &url(~p"/users/register?#{[invite: &1]}")

    case Accounts.invite_user(socket.assigns.current_scope, email, url_fun) do
      {:ok, invitation, :sent} ->
        {:noreply,
         socket
         |> load_signup()
         |> put_flash(:info, gettext("Invitation sent to %{email}.", email: invitation.email))}

      {:ok, invitation, {:error, _reason}} ->
        {:noreply,
         socket
         |> load_signup()
         |> put_flash(
           :error,
           gettext(
             "The invitation for %{email} exists, but the email could not be sent. Try again later.",
             email: invitation.email
           )
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, invite_form: to_form(changeset, as: :invite))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("This page is for administrators."))}
    end
  end

  defp event("create-account", %{"account" => %{"email" => email}}, socket) do
    url_fun = &url(~p"/users/log-in/#{&1}")

    case Accounts.create_user_by_admin(socket.assigns.current_scope, email, url_fun) do
      {:ok, user, :sent} ->
        {:noreply,
         socket
         |> load_signup()
         |> put_flash(
           :info,
           gettext("Account created for %{email}; a log-in link is on its way.",
             email: user.email
           )
         )}

      {:ok, user, {:error, _reason}} ->
        {:noreply,
         socket
         |> load_signup()
         |> put_flash(
           :error,
           gettext(
             "Account created for %{email}, but the email could not be sent. They can ask for a log-in link on the log-in page.",
             email: user.email
           )
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, account_form: to_form(Map.put(changeset, :action, :insert), as: :account))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("This page is for administrators."))}
    end
  end

  defp event("revoke-invitation", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id) do
      Accounts.revoke_signup_invitation(socket.assigns.current_scope, id)
    end

    {:noreply, socket |> load_signup() |> put_flash(:info, gettext("Invitation withdrawn."))}
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

      <div class="set-card" id="system-signup">
        <h2>{gettext("Sign-up")}</h2>
        <p class="hint">
          {gettext(
            "Who may create an account here by themselves. SSO sign-in always works, and the addresses this deployment names as administrators may always register."
          )}
        </p>

        <dl class="system-facts">
          <dt>{gettext("Now")}</dt>
          <dd>
            <span id="signup-mode" class="badge">{mode_label(@signup_mode)}</span>
            <span id="signup-source" class="hint">{source_label(@signup_source)}</span>
          </dd>
          <dt :if={@signup_mode == "open"}>{gettext("Domains")}</dt>
          <dd :if={@signup_mode == "open"} id="signup-domain-list">
            {if @signup_domains == "", do: gettext("any"), else: @signup_domains}
          </dd>
        </dl>

        <p class="hint">
          {gettext(
            "Closed: only you create accounts, below. By invitation: an address invited to a tournament, or invited below. Open: anyone, or only the domains you list."
          )}
        </p>

        <.form for={@signup_form} id="signup-form" phx-submit="save-signup">
          <.input
            field={@signup_form[:mode]}
            type="select"
            label={gettext("Who may sign up")}
            options={[
              {gettext("Closed"), "closed"},
              {gettext("By invitation"), "invite"},
              {pgettext("sign-up mode", "Open"), "open"}
            ]}
          />
          <.input
            field={@signup_form[:domains]}
            type="text"
            label={gettext("Only these email domains (open only, comma-separated, empty for any)")}
            placeholder="club.be, federation.org"
          />
          <p :if={@signup_error} id="signup-error" class="hint system-bad-text">{@signup_error}</p>
          <div class="actions">
            <button id="signup-save" type="submit" class="pe-btn primary">{gettext("Save")}</button>
            <button
              id="signup-clear"
              type="button"
              class="pe-btn"
              phx-click="clear-signup"
              disabled={@signup_source != :ui}
            >
              {if @signup_env_mode,
                do: gettext("Use PAIRINGS_SIGNUP (%{mode})", mode: mode_label(@signup_env_mode)),
                else: gettext("Use the default (by invitation)")}
            </button>
          </div>
        </.form>

        <h3>{gettext("Invite a user")}</h3>
        <p class="hint">
          {gettext(
            "Sends a link to create an account. It works once, only for that address, for seven days, whatever the setting above says."
          )}
        </p>
        <.form for={@invite_form} id="invite-user-form" phx-submit="invite-user">
          <.input field={@invite_form[:email]} type="email" label={gettext("Email")} required />
          <div class="actions">
            <button id="invite-user-send" type="submit" class="pe-btn">
              {gettext("Send invitation")}
            </button>
          </div>
        </.form>

        <div :if={@invitations != []} class="card-table-wrap">
          <table class="pe-table" id="signup-invitations">
            <thead>
              <tr>
                <th>{gettext("Invited")}</th>
                <th>{gettext("By")}</th>
                <th>{gettext("Until")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={inv <- @invitations} id={"signup-invitation-#{inv.id}"}>
                <td>{inv.email}</td>
                <td>{inv.invited_by && inv.invited_by.email}</td>
                <td>{format_time(inv.expires_at)}</td>
                <td>
                  <button
                    type="button"
                    class="pe-btn"
                    phx-click="revoke-invitation"
                    phx-value-id={inv.id}
                    id={"signup-invitation-revoke-#{inv.id}"}
                  >
                    {gettext("Withdraw")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <h3>{gettext("Create an account")}</h3>
        <p class="hint">
          {gettext(
            "Makes the account now, email only, and sends a log-in link. The person never picks a password unless they want one."
          )}
        </p>
        <.form for={@account_form} id="create-account-form" phx-submit="create-account">
          <.input field={@account_form[:email]} type="email" label={gettext("Email")} required />
          <div class="actions">
            <button id="create-account-submit" type="submit" class="pe-btn">
              {gettext("Create account")}
            </button>
          </div>
        </.form>
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

  defp signup_error(:mode), do: gettext("Choose closed, invite or open.")

  defp signup_error({:domain, entry}),
    do: gettext("%{entry} is not an email domain, such as club.be.", entry: inspect(entry))

  defp signup_error(:forbidden), do: gettext("This page is for administrators.")

  defp mode_label("closed"), do: gettext("Closed")
  defp mode_label("invite"), do: gettext("By invitation")
  defp mode_label("open"), do: pgettext("sign-up mode", "Open")

  defp source_label(:ui), do: gettext("set on this page")
  defp source_label(:env), do: gettext("from PAIRINGS_SIGNUP")
  defp source_label(:default), do: gettext("the default")

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
