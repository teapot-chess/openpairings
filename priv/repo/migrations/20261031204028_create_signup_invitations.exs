defmodule PairingsEngine.Repo.Migrations.CreateSignupInvitations do
  use Ecto.Migration

  # An administrator's invitation to create an account
  # (`PairingsEngine.Accounts.SignupInvitation`). Only the token's hash is
  # stored. The inviter is kept for the Admin → System list and forgotten,
  # not cascaded, when that account is deleted: the invitation is still a
  # perfectly good invitation.
  def change do
    create table(:signup_invitations) do
      add :email, :string, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :invited_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:signup_invitations, [:token_hash])
    create index(:signup_invitations, [:email])
  end
end
