defmodule PairingsEngine.Accounts.SignupInvitation do
  @moduledoc """
  An administrator's invitation to create an account, sent from Admin →
  System (`PairingsEngine.Accounts.invite_user/3`).

  The link carries a random token; only its SHA-256 is stored, so a copy of
  the database is not a drawer full of working links. A token is bound to
  the address it was sent to, works once (`used_at`), and stops working
  after `validity_days/0` days. Honoured in every sign-up mode, closed
  included - see `PairingsEngine.Accounts.SignupPolicy`.
  """

  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32
  @validity_in_days 7

  schema "signup_invitations" do
    field :email, :string
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    belongs_to :invited_by, PairingsEngine.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "How long a link works."
  def validity_days, do: @validity_in_days

  @doc """
  A new invitation for `email` from `invited_by_id`, and the URL-safe token
  that goes in the link. The token is not stored; its hash is.
  """
  def build(email, invited_by_id) do
    token = :crypto.strong_rand_bytes(@rand_size)

    invitation = %__MODULE__{
      email: normalize(email),
      token_hash: :crypto.hash(@hash_algorithm, token),
      expires_at: DateTime.add(DateTime.utc_now(:second), @validity_in_days, :day),
      invited_by_id: invited_by_id
    }

    {Base.url_encode64(token, padding: false), invitation}
  end

  @doc """
  The query for the live (unused, unexpired) invitation behind `encoded`,
  or `:error` when the text is not a token at all.
  """
  def live_by_token_query(encoded) when is_binary(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, token} ->
        hash = :crypto.hash(@hash_algorithm, token)
        {:ok, from(i in live_query(), where: i.token_hash == ^hash)}

      :error ->
        :error
    end
  end

  def live_by_token_query(_), do: :error

  @doc "Unused and unexpired invitations."
  def live_query do
    now = DateTime.utc_now(:second)
    from i in __MODULE__, where: is_nil(i.used_at) and i.expires_at > ^now
  end

  @doc false
  def normalize(email), do: email |> to_string() |> String.trim() |> String.downcase()
end
