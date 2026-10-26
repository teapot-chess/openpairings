defmodule PairingsEngine.Repo.Migrations.AddPairedAtToRounds do
  @moduledoc """
  When each round was paired (UTC), for the ITDX file's OpenPairings block
  and the Pairings page. Every path that makes a round's boards sets it; a
  round made before this column existed gets the time of the newest
  `pairing.round_paired` audit row for its number (an unpaired and re-paired
  round has one row per pairing, and the newest is the one that stands), and
  nil when the audit trail has none.
  """
  use Ecto.Migration

  def up do
    alter table(:rounds) do
      add :paired_at, :utc_datetime
    end

    flush()

    execute(backfill_sql())
  end

  @doc false
  # Plain SQL on purpose: a migration must not call code that may change.
  # Apart from `up/0` so a test can run it without a migration runner; safe
  # to run twice (it only fills what is still nil).
  def backfill_sql do
    """
    UPDATE rounds
       SET paired_at = (
             SELECT strftime('%Y-%m-%dT%H:%M:%SZ', MAX(a.inserted_at))
               FROM audit_logs a
              WHERE a.tournament_id = rounds.tournament_id
                AND a.action = 'pairing.round_paired'
                AND json_extract(a.details, '$.round') = rounds.number)
     WHERE paired_at IS NULL
    """
  end

  def down do
    alter table(:rounds) do
      remove :paired_at
    end
  end
end
