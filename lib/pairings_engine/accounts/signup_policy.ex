defmodule PairingsEngine.Accounts.SignupPolicy do
  @moduledoc """
  Who may create an account on a hosted installation by themselves.

  Three modes:

    * `"closed"` - nobody. An administrator creates accounts on Admin →
      System (`PairingsEngine.Accounts.create_user_by_admin/3`).
    * `"invite"` - only an address holding a pending invitation: a
      tournament collaborator or arbiter invitation, or a sign-up
      invitation an administrator sent (`PairingsEngine.Accounts.SignupInvitation`).
      **The default.**
    * `"open"` - anyone, optionally only at the domains listed.

  Two exceptions hold in every mode. The addresses the deployment declares in
  `ADMIN_EMAILS` may always register, because a server nobody can administer
  is a server nobody can open either. And a sign-up invitation an
  administrator sent is honoured whatever the mode: the administrator chose
  that person, which is the whole point of closing the door.

  SSO sign-in (`PairingsEngine.Accounts.find_or_create_from_keycloak/1`)
  never comes through here: the directory already decided who that is.

  ## Where the value comes from

  Resolved like the FIDE list address (`PairingsEngine.Fide.Sync.list_url/0`):
  a value saved on Admin → System wins, then `PAIRINGS_SIGNUP` and
  `PAIRINGS_SIGNUP_DOMAINS` (read and checked once at boot in
  `config/runtime.exs`), then the default. The mode and its domains are saved
  as a pair, so a saved value never mixes with half of the environment's.

  The default is `invite` rather than `open` because a server that lets the
  internet register is a decision, and decisions should be made by somebody
  rather than by an upgrade.

  This module answers questions; it does not create anybody. The one place
  that does, and that asks `check/2` first, is
  `PairingsEngine.Accounts.register_user/2`.
  """

  import Ecto.Query

  alias PairingsEngine.{Authz, Meta, Repo}
  alias PairingsEngine.Accounts.SignupInvitation
  alias PairingsEngine.Tournaments.Collaborator

  @modes ~w(closed invite open)
  @default_mode "invite"

  @mode_key "signup_mode"
  @domains_key "signup_domains"

  @doc "The three modes, most closed first."
  def modes, do: @modes

  @doc "The mode when nothing else says otherwise."
  def default_mode, do: @default_mode

  @doc "The mode in effect."
  def mode, do: stored_mode() || env_mode() || @default_mode

  @doc """
  The domains `open` is limited to, lower case, without an `@`. Empty means
  any domain. Comes from the same place as `mode/0`, as a pair.
  """
  def domains do
    case source() do
      :ui -> stored_domains()
      :env -> env_domains()
      :default -> []
    end
  end

  @doc "Where `mode/0` comes from: `:ui`, `:env` or `:default`."
  def source do
    cond do
      stored_mode() -> :ui
      env_mode() -> :env
      true -> :default
    end
  end

  @doc "Whether anyone may walk in, at least from some domain."
  def open?, do: mode() == "open"

  @doc "`PAIRINGS_SIGNUP` as `config/runtime.exs` checked it, or nil."
  def env_mode do
    case Application.get_env(:pairings_engine, :signup, [])[:mode] do
      mode when mode in @modes -> mode
      _ -> nil
    end
  end

  @doc "`PAIRINGS_SIGNUP_DOMAINS` as `config/runtime.exs` checked it."
  def env_domains do
    case Application.get_env(:pairings_engine, :signup, [])[:domains] do
      list when is_list(list) -> list
      _ -> []
    end
  end

  @doc "The mode saved on Admin → System, or nil."
  def stored_mode do
    case Meta.get(@mode_key) do
      mode when mode in @modes -> mode
      _ -> nil
    end
  rescue
    # No database to ask (a boot before migrations, a process outside the
    # test sandbox): the environment and the default still answer.
    _ -> nil
  end

  defp stored_domains do
    case Meta.get(@domains_key) do
      value when is_binary(value) -> split_domains(value)
      _ -> []
    end
  rescue
    _ -> []
  end

  @doc """
  Saves a mode and its domains, or with `nil` forgets both so the
  environment or the default answers again. The caller validates with
  `validate/2` first and writes the audit row.
  """
  def put(nil, _domains) do
    Meta.delete(@mode_key)
    Meta.delete(@domains_key)
  end

  def put(mode, domains) when mode in @modes and is_list(domains) do
    Meta.put(@mode_key, mode)
    Meta.put(@domains_key, Enum.join(domains, ","))
  end

  @doc """
  Checks a mode and a comma-separated list of domains as somebody typed
  them. Returns `{:ok, {mode, domains}}` or `{:error, :mode | {:domain, text}}`.
  The same rule `config/runtime.exs` applies to the environment.
  """
  def validate(mode, domains_text) do
    with :ok <- validate_mode(mode),
         {:ok, domains} <- parse_domains(domains_text || "") do
      {:ok, {mode, domains}}
    end
  end

  defp validate_mode(mode) when mode in @modes, do: :ok
  defp validate_mode(_), do: {:error, :mode}

  @doc """
  Splits, trims and lower-cases a comma-separated domain list, dropping a
  leading `@`. `{:error, {:domain, entry}}` for the first entry that is not
  a hostname.
  """
  def parse_domains(text) when is_binary(text) do
    domains = split_domains(text)

    case Enum.find(domains, &(not domain?(&1))) do
      nil -> {:ok, domains}
      bad -> {:error, {:domain, bad}}
    end
  end

  defp split_domains(text) do
    text
    |> String.split(",")
    |> Enum.map(&(&1 |> String.trim() |> String.trim_leading("@") |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp domain?(text),
    do:
      Regex.match?(~r/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/, text)

  @doc """
  Whether `email` may create an account by itself, right now.

  Options: `:invitation` - a `SignupInvitation` the caller has already
  matched to this address (`PairingsEngine.Accounts.register_user/2` does
  that from the token in the link).

  Returns `:ok` or `{:error, reason}`, the reason being `:closed`,
  `:invitation_required` or `:domain_not_allowed`.
  """
  def check(email, opts \\ []) do
    email = normalize(email)

    cond do
      email == "" ->
        # Nothing to judge: the changeset says the address is missing.
        :ok

      declared_admin?(email) ->
        :ok

      match?(%SignupInvitation{}, opts[:invitation]) ->
        :ok

      true ->
        check_mode(mode(), email)
    end
  end

  defp check_mode("open", email) do
    cond do
      domains() == [] -> :ok
      domain_of(email) in domains() -> :ok
      pending_collaborator_invitation?(email) -> :ok
      true -> {:error, :domain_not_allowed}
    end
  end

  defp check_mode("invite", email) do
    if pending_collaborator_invitation?(email), do: :ok, else: {:error, :invitation_required}
  end

  defp check_mode(_closed, _email), do: {:error, :closed}

  defp declared_admin?(email), do: email in Enum.map(Authz.declared_admin_emails(), &normalize/1)

  @doc """
  Whether `email` holds a pending tournament invitation (collaborator or
  arbiter) to a tournament that is not in the recycle bin.
  """
  def pending_collaborator_invitation?(email) do
    email = normalize(email)

    Repo.exists?(
      from c in Collaborator,
        join: t in assoc(c, :tournament),
        where: c.status == "pending" and c.email == ^email and is_nil(t.deleted_at)
    )
  end

  defp domain_of(email) do
    case String.split(email, "@") do
      [_local, domain] -> domain
      _ -> ""
    end
  end

  defp normalize(email), do: email |> to_string() |> String.trim() |> String.downcase()
end
