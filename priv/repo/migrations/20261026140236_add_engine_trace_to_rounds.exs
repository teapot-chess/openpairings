defmodule PairingsEngine.Repo.Migrations.AddEngineTraceToRounds do
  @moduledoc """
  `rounds.engine_trace`: Ainalrami's own console output for the round, at
  its normal level, as the ITDX file prints it at the bottom
  (`PairingsEngine.EngineTrace`, `PairingsEngine.ItdxTrace`). Commentary,
  like `rounds.explanation` beside it, and written after the round for an
  individual Swiss - so `rounds_data_version_update` (see
  `DataVersionIgnoresRoundAccounts`) is recreated to leave a write of only
  the account, the trace or both alone, and to name every other column as
  before.

  Rounds paired before this column existed keep nil: there is no going back
  to ask the engine what it printed.
  """
  use Ecto.Migration

  def up do
    alter table(:rounds) do
      add :engine_trace, :map
    end

    flush()

    create_trigger(
      ~s|(OLD."explanation" IS NEW."explanation" AND OLD."engine_trace" IS NEW."engine_trace")|,
      ["engine_trace"]
    )
  end

  def down do
    execute "DROP TRIGGER IF EXISTS rounds_data_version_update"

    alter table(:rounds) do
      remove :engine_trace
    end

    flush()

    create_trigger(~s|OLD."explanation" IS NEW."explanation"|, [])
  end

  defp create_trigger(accounts_unchanged, leave_out) do
    columns =
      repo().query!("PRAGMA table_info(rounds)").rows
      |> Enum.map(&Enum.at(&1, 1))
      |> Kernel.--(["explanation" | leave_out])

    execute "DROP TRIGGER IF EXISTS rounds_data_version_update"

    execute """
    CREATE TRIGGER rounds_data_version_update
    AFTER UPDATE ON rounds
    WHEN #{accounts_unchanged}
      OR #{Enum.map_join(columns, "\n      OR ", &~s|OLD."#{&1}" IS NOT NEW."#{&1}"|)}
    BEGIN
      UPDATE tournaments SET data_version = random()
      WHERE id IN (NEW.tournament_id, OLD.tournament_id);
    END
    """
  end
end
