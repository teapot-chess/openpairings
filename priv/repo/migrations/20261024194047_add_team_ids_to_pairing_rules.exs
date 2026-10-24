defmodule PairingsEngine.Repo.Migrations.AddTeamIdsToPairingRules do
  @moduledoc """
  Pairing rules for team tournaments: `team_ids` holds the teams a
  `team_group` rule keeps apart (a `team_club` rule reads the teams' clubs
  and needs none). Empty for every existing rule.
  """
  use Ecto.Migration

  def change do
    alter table(:pairing_rules) do
      add :team_ids, {:array, :integer}, null: false, default: []
    end
  end
end
