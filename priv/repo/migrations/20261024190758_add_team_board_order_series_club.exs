defmodule PairingsEngine.Repo.Migrations.AddTeamBoardOrderSeriesClub do
  @moduledoc """
  Board order chosen per round, and a series and a club on the team.

  On `tournaments`, `team_board_order`: "roster" (every tournament from before
  the setting: a line-up keeps the roster's board order) or "free" (any roster
  player on any board of a line-up, chosen for each round).

  On `teams`, `series` (a short label such as "Reeks 1", not a separate group:
  teams of every series are paired together) and `club`, both empty text for
  every existing team.
  """
  use Ecto.Migration

  def change do
    alter table(:tournaments) do
      add :team_board_order, :string, null: false, default: "roster"
    end

    alter table(:teams) do
      add :series, :string, null: false, default: ""
      add :club, :string, null: false, default: ""
    end
  end
end
