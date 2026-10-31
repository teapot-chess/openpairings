defmodule PairingsEngine.Repo.Migrations.AddEngineAndProofToRounds do
  @moduledoc """
  Which program paired a round, and the engine's pairing proof for it
  (`PairingsEngine.PairingProofs`). Per round: a desktop update can change
  the engine between two rounds of one event. `proof` is the gzip file as
  published (large, never loaded by default); `proof_sha256` / `proof_bytes`
  describe it without loading it. Every existing round gets nil: nobody
  asked for a proof then.

  The proof is written after the round is saved, by the explanation job, as
  the account and the trace are - so `rounds_data_version_update` (see
  `DataVersionIgnoresRoundAccounts`, `AddEngineTraceToRounds`) is recreated
  to leave a write of only those alone, and to name every other column,
  `engine` and `engine_version` among them, as before.
  """
  use Ecto.Migration

  @commentary ~w(explanation engine_trace proof proof_sha256 proof_bytes)

  def up do
    alter table(:rounds) do
      add :engine, :string
      add :engine_version, :string
      add :proof, :binary
      add :proof_sha256, :string
      add :proof_bytes, :integer
    end

    flush()

    create_trigger(@commentary)
  end

  def down do
    execute "DROP TRIGGER IF EXISTS rounds_data_version_update"

    alter table(:rounds) do
      remove :engine
      remove :engine_version
      remove :proof
      remove :proof_sha256
      remove :proof_bytes
    end

    flush()

    create_trigger(~w(explanation engine_trace))
  end

  defp create_trigger(commentary) do
    columns =
      repo().query!("PRAGMA table_info(rounds)").rows
      |> Enum.map(&Enum.at(&1, 1))
      |> Kernel.--(commentary)

    unchanged = Enum.map_join(commentary, " AND ", &~s|OLD."#{&1}" IS NEW."#{&1}"|)

    execute "DROP TRIGGER IF EXISTS rounds_data_version_update"

    execute """
    CREATE TRIGGER rounds_data_version_update
    AFTER UPDATE ON rounds
    WHEN (#{unchanged})
      OR #{Enum.map_join(columns, "\n      OR ", &~s|OLD."#{&1}" IS NOT NEW."#{&1}"|)}
    BEGIN
      UPDATE tournaments SET data_version = random()
      WHERE id IN (NEW.tournament_id, OLD.tournament_id);
    END
    """
  end
end
