defmodule PairingsEngine.Accounts.SignupPolicyTest do
  # Not async: some tests set the application environment (PAIRINGS_SIGNUP
  # and ADMIN_EMAILS as config/runtime.exs would), which is global.
  use PairingsEngine.DataCase, async: false

  import PairingsEngine.AccountsFixtures

  alias PairingsEngine.{Accounts, Audit, Tournaments}
  alias PairingsEngine.Accounts.{SignupInvitation, SignupPolicy}

  setup do
    signup = Application.get_env(:pairings_engine, :signup)
    admins = Application.get_env(:pairings_engine, :admin_emails)

    on_exit(fn ->
      restore(:signup, signup)
      restore(:admin_emails, admins)
    end)

    Application.delete_env(:pairings_engine, :signup)
    Application.put_env(:pairings_engine, :admin_emails, [])
    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:pairings_engine, key)
  defp restore(key, value), do: Application.put_env(:pairings_engine, key, value)

  defp put_env(mode, domains \\ []),
    do: Application.put_env(:pairings_engine, :signup, mode: mode, domains: domains)

  defp admin_scope do
    user = user_fixture()
    {:ok, admin} = Accounts.set_role(user.email, "admin")
    user_scope_fixture(admin)
  end

  defp email, do: "new#{System.unique_integer([:positive])}@example.com"

  defp refused?(result, fragment) do
    case result do
      {:error, %Ecto.Changeset{} = changeset} ->
        Enum.any?(errors_on(changeset)[:email] || [], &(&1 =~ fragment))

      _ ->
        false
    end
  end

  defp capture_token_url do
    me = self()

    fn token ->
      send(me, {:token, token})
      "http://localhost/users/register?invite=" <> token
    end
  end

  describe "where the mode comes from" do
    test "is invite when nothing says otherwise" do
      assert SignupPolicy.mode() == "invite"
      assert SignupPolicy.source() == :default
      assert SignupPolicy.domains() == []
    end

    test "the environment beats the default" do
      put_env("open", ["club.be"])
      assert SignupPolicy.mode() == "open"
      assert SignupPolicy.domains() == ["club.be"]
      assert SignupPolicy.source() == :env
    end

    test "a value saved from the admin page beats the environment, domains and all" do
      put_env("open", ["club.be"])
      SignupPolicy.put("closed", [])

      assert SignupPolicy.mode() == "closed"
      assert SignupPolicy.domains() == []
      assert SignupPolicy.source() == :ui

      SignupPolicy.put(nil, [])
      assert SignupPolicy.mode() == "open"
      assert SignupPolicy.source() == :env
    end

    test "validate/2 rejects an unknown mode and a domain that is not one" do
      assert {:ok, {"open", ["club.be", "fed.org"]}} =
               SignupPolicy.validate("open", " @Club.be, fed.org,, ")

      assert {:error, :mode} = SignupPolicy.validate("ajar", "")
      assert {:error, {:domain, "not a domain"}} = SignupPolicy.validate("open", "not a domain")
      assert {:error, {:domain, "a@b.c"}} = SignupPolicy.validate("open", "a@b.c")
    end
  end

  describe "register_user/2 in each mode" do
    test "invite (the default) refuses an address with no invitation" do
      assert refused?(Accounts.register_user(%{email: email()}), "by invitation")
    end

    test "invite lets in an address holding a pending tournament invitation" do
      scope = user_scope_fixture()

      {:ok, tournament} =
        Tournaments.create_tournament(scope, %{"name" => "T", "type" => "swiss"})

      invited = email()
      {:ok, _} = Tournaments.add_collaborator(scope, tournament, invited)

      assert {:ok, user} = Accounts.register_user(%{email: String.upcase(invited)})
      assert user.email == String.upcase(invited) or user.email == invited
    end

    test "invite does not count an invitation to a tournament in the recycle bin" do
      scope = user_scope_fixture()

      {:ok, tournament} =
        Tournaments.create_tournament(scope, %{"name" => "T", "type" => "swiss"})

      invited = email()
      {:ok, _} = Tournaments.add_collaborator(scope, tournament, invited)
      {:ok, _} = Tournaments.soft_delete_tournament(tournament)

      assert refused?(Accounts.register_user(%{email: invited}), "by invitation")
    end

    test "closed refuses everyone, invited to a tournament or not" do
      SignupPolicy.put("closed", [])
      scope = user_scope_fixture()

      {:ok, tournament} =
        Tournaments.create_tournament(scope, %{"name" => "T", "type" => "swiss"})

      invited = email()
      {:ok, _} = Tournaments.add_collaborator(scope, tournament, invited)

      assert refused?(Accounts.register_user(%{email: email()}), "does not take sign-ups")
      assert refused?(Accounts.register_user(%{"email" => invited}), "does not take sign-ups")
    end

    test "open takes anyone" do
      SignupPolicy.put("open", [])
      assert {:ok, _} = Accounts.register_user(%{email: email()})
    end

    test "open with domains takes only those domains" do
      SignupPolicy.put("open", ["club.be"])

      assert {:ok, _} = Accounts.register_user(%{email: "someone@Club.be"})
      assert refused?(Accounts.register_user(%{email: email()}), "limited to some email domains")
      assert refused?(Accounts.register_user(%{email: "x@sub.club.be"}), "limited")
    end

    test "the SSO domain stays refused even on an open server" do
      SignupPolicy.put("open", [])
      assert refused?(Accounts.register_user(%{email: "a@zerotwo.cloud"}), "SSO")
    end
  end

  describe "bootstrap: the deployment's administrators" do
    test "may register in every mode, matched case-insensitively" do
      Application.put_env(:pairings_engine, :admin_emails, ["boss@example.org"])

      SignupPolicy.put("closed", [])
      assert {:ok, user} = Accounts.register_user(%{email: "Boss@Example.org"})
      assert user

      Application.put_env(:pairings_engine, :admin_emails, ["second@example.org"])
      SignupPolicy.put("open", ["club.be"])
      assert {:ok, _} = Accounts.register_user(%{email: "second@example.org"})
    end

    test "nobody else gets in on the strength of that list" do
      Application.put_env(:pairings_engine, :admin_emails, ["boss@example.org"])
      SignupPolicy.put("closed", [])
      assert refused?(Accounts.register_user(%{email: "boss@example.org.evil.com"}), "sign-ups")
    end
  end

  describe "SSO" do
    test "creates the account whatever the mode" do
      SignupPolicy.put("closed", [])

      assert {:ok, user} =
               Accounts.find_or_create_from_keycloak(%{
                 sub: "sub-#{System.unique_integer([:positive])}",
                 email: email(),
                 email_verified: true
               })

      assert user.confirmed_at
    end
  end

  describe "an administrator's sign-up invitation" do
    test "lets that address register in a closed server, once" do
      SignupPolicy.put("closed", [])
      scope = admin_scope()
      invited = email()

      assert {:ok, invitation, :sent} = Accounts.invite_user(scope, invited, capture_token_url())
      assert_received {:token, token}
      assert invitation.email == invited
      assert [%SignupInvitation{}] = Accounts.list_signup_invitations()

      assert Accounts.get_live_signup_invitation(token).id == invitation.id
      assert {:ok, user} = Accounts.register_user(%{email: invited}, invite_token: token)
      assert user.email == invited

      # Spent.
      assert Accounts.get_live_signup_invitation(token) == nil
      assert Accounts.list_signup_invitations() == []

      assert [_] = Audit.list_machine_wide(actions: ["accounts.signup_invited"])
    end

    test "a spent token cannot open a second account" do
      SignupPolicy.put("closed", [])
      invited = email()
      {:ok, _, _} = Accounts.invite_user(admin_scope(), invited, capture_token_url())
      assert_received {:token, token}

      {:ok, user} = Accounts.register_user(%{email: invited}, invite_token: token)
      Repo.delete!(user)

      assert refused?(Accounts.register_user(%{email: invited}, invite_token: token), "sign-ups")
    end

    test "is bound to the address it was sent to" do
      SignupPolicy.put("closed", [])
      {:ok, _, _} = Accounts.invite_user(admin_scope(), email(), capture_token_url())
      assert_received {:token, token}

      assert refused?(Accounts.register_user(%{email: email()}, invite_token: token), "sign-ups")
      # And the token is still there for its owner.
      assert Accounts.get_live_signup_invitation(token)
    end

    test "is not needed by the address alone: without the token it is refused" do
      SignupPolicy.put("closed", [])
      invited = email()
      {:ok, _, _} = Accounts.invite_user(admin_scope(), invited, capture_token_url())

      assert refused?(Accounts.register_user(%{email: invited}), "sign-ups")
    end

    test "expires" do
      SignupPolicy.put("closed", [])
      invited = email()
      {:ok, invitation, _} = Accounts.invite_user(admin_scope(), invited, capture_token_url())
      assert_received {:token, token}

      invitation
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1, :second))
      |> Repo.update!()

      assert Accounts.get_live_signup_invitation(token) == nil
      assert refused?(Accounts.register_user(%{email: invited}, invite_token: token), "sign-ups")
    end

    test "a new invitation withdraws the old link; revoking withdraws the new one" do
      scope = admin_scope()
      invited = email()
      {:ok, _, _} = Accounts.invite_user(scope, invited, capture_token_url())
      assert_received {:token, first}
      {:ok, second, _} = Accounts.invite_user(scope, invited, capture_token_url())
      assert_received {:token, _second_token}

      assert Accounts.get_live_signup_invitation(first) == nil
      assert :ok = Accounts.revoke_signup_invitation(scope, second.id)
      assert Accounts.list_signup_invitations() == []
    end

    test "garbage tokens are nobody's invitation" do
      assert Accounts.get_live_signup_invitation("not-base64!!") == nil
      assert Accounts.get_live_signup_invitation(nil) == nil

      assert refused?(
               Accounts.register_user(%{email: email()}, invite_token: "AAAA"),
               "invitation"
             )
    end

    test "refuses an address that already has an account" do
      existing = user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Accounts.invite_user(admin_scope(), existing.email, & &1)
    end
  end

  describe "administrator-only functions refuse everyone else" do
    test "policy, invitations and account creation" do
      scope = user_scope_fixture()

      assert {:error, :forbidden} = Accounts.update_signup_policy(scope, "open", "")
      assert SignupPolicy.mode() == "invite"
      assert {:error, :forbidden} = Accounts.invite_user(scope, email(), & &1)
      assert {:error, :forbidden} = Accounts.create_user_by_admin(scope, email(), & &1)
      assert {:error, :forbidden} = Accounts.revoke_signup_invitation(scope, 1)
    end

    test "a role taken away after the page loaded no longer works" do
      scope = admin_scope()
      {:ok, _} = Accounts.set_role(scope.user.email, "owner")

      assert {:error, :forbidden} = Accounts.update_signup_policy(scope, "open", "")
    end
  end

  describe "update_signup_policy/3" do
    test "saves, audits the change, and clears back to the environment" do
      put_env("open")
      scope = admin_scope()

      assert :ok = Accounts.update_signup_policy(scope, "open", "club.be")
      assert SignupPolicy.source() == :ui

      [row] = Audit.list_machine_wide(actions: ["accounts.signup_policy_changed"])
      assert row.details["changed_fields"]["domains"] == ["", "club.be"]

      # Saving the same thing again is not worth a row.
      assert :ok = Accounts.update_signup_policy(scope, "open", "club.be")
      assert [_] = Audit.list_machine_wide(actions: ["accounts.signup_policy_changed"])

      assert :ok = Accounts.update_signup_policy(scope, nil)
      assert SignupPolicy.source() == :env
      assert SignupPolicy.domains() == []
    end

    test "refuses a bad value without saving it" do
      scope = admin_scope()
      assert {:error, {:domain, _}} = Accounts.update_signup_policy(scope, "open", "nope")
      assert {:error, :mode} = Accounts.update_signup_policy(scope, "wide-open", "")
      assert SignupPolicy.source() == :default
    end
  end

  describe "create_user_by_admin/3" do
    test "makes the account and mails a log-in link, whatever the mode" do
      SignupPolicy.put("closed", [])
      address = email()

      assert {:ok, user, :sent} =
               Accounts.create_user_by_admin(admin_scope(), address, capture_token_url())

      assert user.email == address
      assert_received {:token, token}

      assert {:ok, {user, _}} = Accounts.login_user_by_magic_link(token)
      assert user.confirmed_at
      assert [_] = Audit.list_machine_wide(actions: ["accounts.user_created"])
    end
  end
end
