defmodule PairingsEngine.Repo.Migrations.AddSwissVariantToTournaments do
  @moduledoc """
  `tournaments.swiss_variant`: which FIDE Swiss system pairs a Swiss
  tournament - "dutch" (C.04.3, every tournament until now) or "dubov"
  (C.04.4.1). Every existing tournament is Dutch, because that is what
  paired it.
  """
  use Ecto.Migration

  def change do
    alter table(:tournaments) do
      add :swiss_variant, :string, null: false, default: "dutch"
    end
  end
end
