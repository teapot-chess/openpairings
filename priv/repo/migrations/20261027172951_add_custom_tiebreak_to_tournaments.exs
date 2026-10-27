defmodule PairingsEngine.Repo.Migrations.AddCustomTiebreakToTournaments do
  use Ecto.Migration

  # The tournament's own tie-break formula (`PairingsEngine.Tiebreaks.Custom`),
  # read when `CUSTOM` is on the tie-break list. NULL for every tournament
  # that has never built one.
  def change do
    alter table(:tournaments) do
      add :custom_tiebreak, :map
    end
  end
end
