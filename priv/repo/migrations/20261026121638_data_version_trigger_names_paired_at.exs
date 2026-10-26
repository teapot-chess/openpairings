defmodule PairingsEngine.Repo.Migrations.DataVersionTriggerNamesPairedAt do
  @moduledoc """
  Recreates `rounds_data_version_update` (see
  `DataVersionIgnoresRoundAccounts`) so it names `paired_at`
  (`AddPairedAtToRounds`). The Pairings page and the ITDX file read it, so a
  change to it should be noticed like any other.
  """
  use Ecto.Migration

  @added ~w(paired_at)

  def up, do: create_trigger([])

  def down, do: create_trigger(@added)

  defp create_trigger(leave_out) do
    columns =
      repo().query!("PRAGMA table_info(rounds)").rows
      |> Enum.map(&Enum.at(&1, 1))
      |> Kernel.--(["explanation" | leave_out])

    execute "DROP TRIGGER IF EXISTS rounds_data_version_update"

    execute """
    CREATE TRIGGER rounds_data_version_update
    AFTER UPDATE ON rounds
    WHEN OLD."explanation" IS NEW."explanation"
      OR #{Enum.map_join(columns, "\n      OR ", &~s|OLD."#{&1}" IS NOT NEW."#{&1}"|)}
    BEGIN
      UPDATE tournaments SET data_version = random()
      WHERE id IN (NEW.tournament_id, OLD.tournament_id);
    END
    """
  end
end
