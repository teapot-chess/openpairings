defmodule PairingsEngine.Repo.Migrations.AddTeamPrimaryScoreTpnLimitAndDraw do
  @moduledoc """
  Three team-Swiss options, all on `tournaments`:

    * `team_primary_score` - "match_points" (C.04.6 Art. 1.2.2's default, and
      what every existing tournament was paired and ranked by) or
      "game_points" (Art. 1.2.1: the competition's rules may name game
      points the primary score);
    * `team_tpn_until_round` - team numbers can be corrected until this round
      is paired; 4 is C.04.2 Art. 2.3's limit and what every existing
      tournament had;
    * `teams_drawn_at` - when the order of the teams was last drawn by lot on
      the Teams page; nil for every existing tournament, since none was.
  """
  use Ecto.Migration

  def change do
    alter table(:tournaments) do
      add :team_primary_score, :string, null: false, default: "match_points"
      add :team_tpn_until_round, :integer, null: false, default: 4
      add :teams_drawn_at, :utc_datetime
    end
  end
end
