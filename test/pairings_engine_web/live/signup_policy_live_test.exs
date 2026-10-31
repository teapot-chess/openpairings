defmodule PairingsEngineWeb.SignupPolicyLiveTest do
  # Not async: the bootstrap test sets ADMIN_EMAILS in the application
  # environment, which is global.
  use PairingsEngineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import PairingsEngine.AccountsFixtures

  @moduletag :capture_log

  alias PairingsEngine.{Accounts, Audit, Tournaments}
  alias PairingsEngine.Accounts.SignupPolicy

  setup do
    admins = Application.get_env(:pairings_engine, :admin_emails)

    on_exit(fn ->
      if admins,
        do: Application.put_env(:pairings_engine, :admin_emails, admins),
        else: Application.delete_env(:pairings_engine, :admin_emails)
    end)

    Application.put_env(:pairings_engine, :admin_emails, [])
    :ok
  end

  defp email, do: "new#{System.unique_integer([:positive])}@example.com"

  defp submit(lv, address) do
    lv |> form("#registration_form", user: %{email: address}) |> render_submit()
  end

  describe "the sign-up page" do
    test "invite (the default) says so, and turns away an address with no invitation",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      assert has_element?(lv, "#signup-invite-only")
      # What the deploy script reads to report the live mode.
      assert has_element?(lv, ~s(#signup-card[data-signup-mode="invite"]))

      address = email()
      html = submit(lv, address)
      assert html =~ "by invitation"
      refute Accounts.get_user_by_email(address)
    end

    test "invite takes an address invited to a tournament", %{conn: conn} do
      scope = user_scope_fixture()

      {:ok, tournament} =
        Tournaments.create_tournament(scope, %{"name" => "T", "type" => "swiss"})

      invited = email()
      {:ok, _} = Tournaments.add_collaborator(scope, tournament, invited)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _lv, html} = lv |> submit(invited) |> follow_redirect(conn, ~p"/users/log-in")
      assert html =~ "An email was sent"
      assert Accounts.get_user_by_email(invited)
    end

    test "closed says the server takes no sign-ups and refuses a direct submit", %{conn: conn} do
      SignupPolicy.put("closed", [])
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      assert has_element?(lv, "#signup-closed")

      # The form is folded away for administrators, but still in the page:
      # submitting it anyway is the bypass attempt, and the context says no.
      address = email()
      assert submit(lv, address) =~ "does not take sign-ups"
      refute Accounts.get_user_by_email(address)

      # And a hand-made event with no form at all.
      render_hook(lv, "save", %{"user" => %{"email" => address}})
      refute Accounts.get_user_by_email(address)
    end

    test "closed still lets the deployment's administrator register", %{conn: conn} do
      SignupPolicy.put("closed", [])
      Application.put_env(:pairings_engine, :admin_emails, ["boss@example.org"])

      {:ok, lv, _html} = live(conn, ~p"/users/register")
      assert {:ok, _lv, _html} = lv |> submit("boss@example.org") |> follow_redirect(conn)
      assert Accounts.get_user_by_email("boss@example.org")
    end

    test "open with domains names them and refuses the rest", %{conn: conn} do
      SignupPolicy.put("open", ["club.be"])
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      assert has_element?(lv, "#signup-domains", "@club.be")

      assert submit(lv, "x@elsewhere.org") =~ "limited to some email domains"
      refute Accounts.get_user_by_email("x@elsewhere.org")
    end

    test "an invitation link fills in the address and opens a closed server once",
         %{conn: conn} do
      SignupPolicy.put("closed", [])
      admin = user_fixture()
      {:ok, admin} = Accounts.set_role(admin.email, "admin")
      invited = email()
      me = self()

      {:ok, _, _} =
        Accounts.invite_user(user_scope_fixture(admin), invited, fn token ->
          send(me, {:token, token})
          token
        end)

      assert_received {:token, token}

      {:ok, lv, html} = live(conn, ~p"/users/register?invite=#{token}")
      assert has_element?(lv, "#signup-invited")
      assert html =~ invited

      {:ok, _lv, _html} = lv |> submit(invited) |> follow_redirect(conn, ~p"/users/log-in")
      assert Accounts.get_user_by_email(invited)

      # The link is spent: the page is a closed server's page again.
      {:ok, lv, _html} = live(conn, ~p"/users/register?invite=#{token}")
      assert has_element?(lv, "#signup-closed")
    end
  end

  describe "the log-in page" do
    test "offers sign-up only when the server is open", %{conn: conn} do
      SignupPolicy.put("open", [])
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      assert has_element?(lv, "#register-link")
      assert has_element?(lv, "#hero-register-link")

      SignupPolicy.put("invite", [])
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      refute has_element?(lv, "#register-link")
      refute has_element?(lv, "#hero-register-link")
      refute has_element?(lv, "#register-invited-link")

      SignupPolicy.put("closed", [])
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")
      refute has_element?(lv, "#register-link")
      refute has_element?(lv, "#hero-register-link")
    end

    test "invite: somebody sent here by an invitation link is offered the way in",
         %{conn: conn} do
      conn = get(conn, ~p"/invites/some-token")
      assert redirected_to(conn) == ~p"/users/log-in"

      {:ok, lv, _html} = live(recycle(conn), ~p"/users/log-in")
      assert has_element?(lv, "#register-invited-link")
      refute has_element?(lv, "#register-link")
    end
  end

  describe "the Sign-up card on Admin → System" do
    setup :register_and_log_in_user

    setup %{conn: conn, user: user} do
      {:ok, admin} = Accounts.set_role(user.email, "admin")
      {:ok, conn: log_in_user(conn, admin), admin: admin}
    end

    test "shows the mode and where it comes from, saves a change and audits it",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/system")
      assert has_element?(lv, "#signup-mode", "By invitation")
      assert has_element?(lv, "#signup-source", "the default")

      lv
      |> form("#signup-form", signup: %{mode: "open", domains: "club.be"})
      |> render_submit()

      assert SignupPolicy.mode() == "open"
      assert SignupPolicy.domains() == ["club.be"]
      assert has_element?(lv, "#signup-source", "set on this page")
      assert has_element?(lv, "#signup-domain-list", "club.be")
      assert [_] = Audit.list_machine_wide(actions: ["accounts.signup_policy_changed"])

      lv |> element("#signup-clear") |> render_click()
      assert SignupPolicy.source() == :default
    end

    test "a bad domain is refused with a reason", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/system")

      lv
      |> form("#signup-form", signup: %{mode: "open", domains: "not a domain"})
      |> render_submit()

      assert has_element?(lv, "#signup-error")
      assert SignupPolicy.source() == :default
    end

    test "invites a user and lists the invitation until it is withdrawn", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/system")
      invited = email()

      lv |> form("#invite-user-form", invite: %{email: invited}) |> render_submit()

      [invitation] = Accounts.list_signup_invitations()
      assert invitation.email == invited
      assert has_element?(lv, "#signup-invitation-#{invitation.id}", invited)

      lv |> element("#signup-invitation-revoke-#{invitation.id}") |> render_click()
      assert Accounts.list_signup_invitations() == []
    end

    test "creates an account", %{conn: conn} do
      SignupPolicy.put("closed", [])
      {:ok, lv, _html} = live(conn, ~p"/admin/system")
      address = email()

      lv |> form("#create-account-form", account: %{email: address}) |> render_submit()
      assert Accounts.get_user_by_email(address)
    end
  end

  describe "the Sign-up card for anyone else" do
    setup :register_and_log_in_user

    test "the page does not open (the context refuses them too: signup_policy_test.exs)", %{
      conn: conn
    } do
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/system")
      assert SignupPolicy.mode() == "invite"
    end
  end
end
