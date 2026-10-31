defmodule PairingsEngine.Repo.Migrations.AddSeriesIdToTournaments do
  use Ecto.Migration

  # The id of the series (the same event in other years) a tournament belongs
  # to; nil for one that is in none. Minted by `PairingsEngine.TournamentSeries`.
  def change do
    alter table(:tournaments) do
      add :series_id, :string
    end

    create index(:tournaments, [:series_id])
  end
end
