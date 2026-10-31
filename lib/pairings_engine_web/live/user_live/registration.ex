defmodule PairingsEngineWeb.UserLive.Registration do
  use PairingsEngineWeb, :live_view

  alias PairingsEngine.{Accounts, RateLimit}
  alias PairingsEngine.Accounts.{SignupPolicy, User}
  alias PairingsEngineWeb.ClientIp

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      publish_status={assigns[:publish_status]}
      update_notice={assigns[:update_notice]}
      fide_notice={assigns[:fide_notice]}
      flash={@flash}
      current_path={assigns[:current_path]}
      current_scope={@current_scope}
    >
      <div class="auth-wrap">
        <aside class="auth-hero">
          <div class="auth-hero-inner">
            <div class="auth-hero-brand">
              <svg
                class="auth-hero-mark"
                viewBox="0 0 64 48"
                xmlns="http://www.w3.org/2000/svg"
                aria-hidden="true"
              >
                <defs>
                  <linearGradient id="reg-orb" x1="0%" y1="0%" x2="100%" y2="100%">
                    <stop offset="0%" stop-color="#5fbf8f" />
                    <stop offset="100%" stop-color="#2e5e44" />
                  </linearGradient>
                </defs>

                <path
                  d="M22,18 Q10,10 1,14 Q8,22 10,30 Q16,32 22,30 Q26,26 22,18 Z"
                  fill="#f7f3e8"
                  stroke="#12150f"
                  stroke-width="3"
                  stroke-linejoin="round"
                />
                <path
                  d="M42,18 Q54,10 63,14 Q56,22 54,30 Q48,32 42,30 Q38,26 42,18 Z"
                  fill="#f7f3e8"
                  stroke="#12150f"
                  stroke-width="3"
                  stroke-linejoin="round"
                />
                <circle cx="32" cy="24" r="14" fill="url(#reg-orb)" stroke="#12150f" stroke-width="3" />
                <ellipse
                  cx="27"
                  cy="18"
                  rx="4"
                  ry="6"
                  fill="#ffffff"
                  opacity="0.5"
                  transform="rotate(-25 27 18)"
                />
              </svg>
              <span class="auth-hero-name">Open<strong>Pairings</strong></span>
            </div>

            <h1 class="auth-hero-title">{gettext("Create your free account.")}</h1>

            <p class="auth-hero-sub">
              {gettext(
                "One account runs every event you organise - set up in seconds, no credit card, invite co-arbiters whenever you like."
              )}
            </p>

            <ul class="auth-features">
              <li>
                <.icon name="hero-check-circle-mini" class="size-5" /> {gettext(
                  "Swiss (Dutch), round robin, Keizer & team tournaments"
                )}
              </li>

              <li>
                <.icon name="hero-check-circle-mini" class="size-5" /> {gettext(
                  "Ainalrami · our own FIDE 2026 Swiss engine, validated against 2.5 billion pairings"
                )}
              </li>

              <li>
                <.icon name="hero-check-circle-mini" class="size-5" /> {gettext(
                  "FIDE C.07 tie-breaks, title norms & a pairing explanation for every round"
                )}
              </li>

              <li>
                <.icon name="hero-check-circle-mini" class="size-5" /> {gettext(
                  "Publish to OpenResults · live results, standings & team pages, only what you choose"
                )}
              </li>

              <li>
                <.icon name="hero-check-circle-mini" class="size-5" /> {gettext(
                  "Invite co-arbiters · run a tournament together, with a full audit trail"
                )}
              </li>

              <li>
                <.icon name="hero-check-circle-mini" class="size-5" /> {gettext(
                  "TRF-2026, TRF, SWAR & PGN import / export, plus FIDE & KBSB rating lists"
                )}
              </li>
            </ul>

            <div class="auth-hero-cta">
              <span>{gettext("Already have an account?")}</span>
              <.link navigate={~p"/users/log-in"} class="auth-hero-cta-btn">
                {gettext("Log in")} <span aria-hidden="true">→</span>
              </.link>
            </div>
          </div>
        </aside>

        <div class="auth-panel">
          <%!-- data-signup-mode: what the deploy script's check reads. --%>
          <div id="signup-card" class="auth-card" data-signup-mode={@mode}>
            <h2 class="auth-card-title">{gettext("Create an account")}</h2>

            <%!-- Who may sign up here, said before anybody types: see
                 `PairingsEngine.Accounts.SignupPolicy`. The form below meets
                 the same rule in `Accounts.register_user/2` either way. --%>
            <%= cond do %>
              <% @invitation -> %>
                <div id="signup-invited" class="auth-notice">
                  <.icon name="hero-envelope-open" class="size-5 shrink-0" />
                  <span>
                    {gettext(
                      "You were invited to this server. Use the address the invitation went to: %{email}.",
                      email: @invitation.email
                    )}
                  </span>
                </div>
              <% @mode == "closed" -> %>
                <div id="signup-closed" class="auth-notice">
                  <.icon name="hero-lock-closed" class="size-5 shrink-0" />
                  <span>
                    {gettext(
                      "This server doesn't take sign-ups. Its administrator creates the accounts; if you were expecting one, ask them, or log in if you already have one."
                    )}
                  </span>
                </div>
              <% @mode == "invite" -> %>
                <div id="signup-invite-only" class="auth-notice">
                  <.icon name="hero-envelope" class="size-5 shrink-0" />
                  <span>
                    {gettext(
                      "This server takes new accounts by invitation. You need an invitation to a tournament, or from the administrator, sent to the address you use below."
                    )}
                  </span>
                </div>
              <% @domains != [] -> %>
                <div id="signup-domains" class="auth-notice">
                  <.icon name="hero-information-circle" class="size-5 shrink-0" />
                  <span>
                    {gettext("Sign-up here is for addresses at %{domains}.",
                      domains: Enum.map_join(@domains, ", ", &("@" <> &1))
                    )}
                  </span>
                </div>
              <% true -> %>
            <% end %>

            <p :if={@mode != "closed" or @invitation} class="auth-card-sub">
              {gettext("Enter your email and we'll send a magic link to confirm it.")}
            </p>

            <%= if @mode == "closed" and is_nil(@invitation) do %>
              <details id="signup-admin" class="auth-form">
                <summary class="auth-link">{gettext("Administrator of this server?")}</summary>
                <p class="auth-card-sub">
                  {gettext(
                    "The addresses this server's deployment names as administrators can still register here."
                  )}
                </p>
                <.registration_form form={@form} />
              </details>
            <% else %>
              <.registration_form form={@form} />
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp registration_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="registration_form"
      class="auth-form"
      phx-submit="save"
      phx-change="validate"
    >
      <.input
        field={@form[:email]}
        type="email"
        label={gettext("Email")}
        autocomplete="username"
        spellcheck="false"
        required
        phx-mounted={JS.focus()}
      />
      <button
        type="submit"
        phx-disable-with={gettext("Creating account...")}
        class="pe-btn primary auth-submit"
      >
        {gettext("Create a free account")} <span aria-hidden="true">→</span>
      </button>
    </.form>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: PairingsEngineWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(params, _session, socket) do
    # The token from an administrator's invitation link, kept in the socket
    # rather than in the form: it is not something the person types, and
    # `Accounts.register_user/2` checks it against the address anyway.
    token = if is_binary(params["invite"]), do: params["invite"]
    invitation = Accounts.get_live_signup_invitation(token)

    attrs = if invitation, do: %{"email" => invitation.email}, else: %{}
    changeset = Accounts.change_user_email(%User{}, attrs, validate_unique: false)

    # Connect info is only readable while mounting; kept for the send limit in
    # `handle_event("save", ...)`. Registration will mail ANY address typed
    # here, so this endpoint needs the same throttle as the log-in form.
    {:ok,
     socket
     |> assign(
       client_ip: ClientIp.from_socket(socket),
       mode: SignupPolicy.mode(),
       domains: SignupPolicy.domains(),
       invitation: invitation,
       invite_token: invitation && token
     )
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    limits = rate_limits(socket, user_params["email"])

    if Enum.all?(limits, fn {bucket, key} -> RateLimit.allow?(bucket, key) end) do
      Enum.each(limits, fn {bucket, key} -> RateLimit.record(bucket, key) end)
      do_register(socket, user_params)
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext("Too many sign-up emails from here just now. Try again in a few minutes.")
       )}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp do_register(socket, user_params) do
    case Accounts.register_user(user_params, invite_token: socket.assigns.invite_token) do
      {:ok, user} ->
        case Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}")) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               gettext("An email was sent to %{email}, please access it to confirm your account.",
                 email: user.email
               )
             )
             |> push_navigate(to: ~p"/users/log-in")}

          {:error, reason} ->
            require Logger
            Logger.error("Failed to send login instructions to #{user.email}: #{inspect(reason)}")

            {:noreply,
             socket
             |> put_flash(
               :error,
               gettext(
                 "Account created successfully, but the email could not be sent. Try again later or contact the administrator."
               )
             )
             |> push_navigate(to: ~p"/users/log-in")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Shares the `:login_email` bucket with the log-in form on purpose: both
  # send a magic link, so counting them together is what actually bounds how
  # much mail one address (or one client) can trigger. Password sign-in no
  # longer reads it (see `UserSessionController`), so spending it costs the
  # victim a quarter of an hour of mail, not their way in.
  defp rate_limits(socket, email) do
    recipient = email |> to_string() |> String.trim() |> String.downcase()

    case socket.assigns[:client_ip] do
      nil -> [{:login_email, recipient}]
      ip -> [{:login_email, recipient}, {:login_client, ip}]
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
