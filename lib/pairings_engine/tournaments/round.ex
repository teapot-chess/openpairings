defmodule PairingsEngine.Tournaments.Round do
  use Ecto.Schema
  import Ecto.Changeset
  require Ecto.Query

  schema "rounds" do
    field :number, :integer
    # The Chess960 starting position drawn for this round (0..959, the
    # standard numbering - `PairingsEngine.Chess960`), nil while none is.
    # Not cast: written only by `Chess960.draw_for_round/3`.
    field :chess960_position, :integer
    field :date, :string, default: ""
    field :status, :string, default: "pairing"
    # When this round becomes visible on the public pairings page - see
    # `PairingsEngine.Tournaments.compute_published_at/2` (set once, at
    # pairing time, from the tournament's `publish_mode` and its delay) and
    # `round_published?/2` (the actual visibility check). `nil` means "not
    # published"; never published retroactively by a background job -
    # visibility is just "is this timestamp in the past", checked live.
    field :published_at, :utc_datetime

    # When this round's boards were made (UTC): set by every path that pairs
    # a round, so a round paired again after an unpair carries the new time.
    # nil for a round imported from a file that does not say, and for an old
    # round with no audit row to take it from. Carried by an export file (the only
    # caller of `changeset/2` that casts it). Shown on the Pairings page and
    # written in the ITDX file; never an input to a pairing.
    field :paired_at, :utc_datetime

    # This round's own due-at for `PairingsEngine.Publishing.promote_due_rounds/1` -
    # a copy of `published_at`, set ONLY when it was genuinely in the future
    # at pairing time (see `Tournaments.due_publish_at/1`). Cleared the
    # moment the sweep acts on it, or when the round is published/unpublished
    # by hand (`Tournaments.publish_round_now/1`, `unpublish_round/1`), which
    # is what makes the sweep idempotent and a manual override a real
    # override. `nil` for every round before this field existed, and for
    # every round that does not need a background wake-up (by hand, or the
    # automation's pairings step already due when paired - no delay, or the
    # delay already elapsed). Not cast - written only by the pairing engines
    # and the two functions above, same reasoning as `virtual_points`.
    field :publish_due_at, :utc_datetime

    # The "Results round N" switch: whether the results typed into this
    # round may travel with its published pairings. `false` for every new
    # round - the pairings still publish, the boards go out without results
    # (`PairingsEngine.Snapshot` withholds them). Read through
    # `Tournaments.results_public?/2`, never directly: public standings after
    # this round, and the automation's results step, make the results public
    # whatever this says.
    #
    # Written only by `Tournaments.publish_results/2`,
    # `unpublish_results/2` and the pairings-unpublish cascades, and NOT cast
    # by `changeset/2` - same reasoning as `Tournament.standings_through`.
    # The migration that added it backfilled `true` on every round already
    # published, because those results were public at the time.
    field :results_public, :boolean, default: false

    # The highest level the automation may bring this round to - set when the
    # arbiter chooses a level on the Pairings page that is BELOW what the
    # automation would give the round (`Tournaments.set_round_publish_level/3`),
    # so a round taken down by hand stays down. `nil` - the usual case - is
    # no limit. Only the automation's derived steps read it (results live,
    # standings once finished); what the arbiter chose by hand is stored in
    # the fields above and never capped. Not cast, like `results_public`.
    field :publish_cap, :integer

    # What the pairing engine reported about its own decision, captured when
    # the round was paired - see `PairingsEngine.Pairing.explanation/3`. Only
    # Ainalrami produces one; every round paired before this column existed
    # (or by the external engine this app once ran) leaves it nil and the rationale page falls back to
    # reconstructing brackets from the round's inputs and outputs.
    #
    # Stored rather than recomputed because it is a record of what happened,
    # not a derivation of current state: a round can be edited by hand
    # afterwards (`pairing.players_swapped` and friends), and re-deriving
    # then would explain a pairing the engine never produced.
    field :explanation, :map

    # Ainalrami's own console output for this round at its normal level -
    # the engine telling how it paired, in its own words - captured for the
    # ITDX file (`PairingsEngine.EngineTrace`): `%{"version" => 1,
    # "kind" => "individual" | "team", "sections" => [...]}`. Commentary
    # like `explanation`, read by nothing but the ITDX file, and never an
    # input to a pairing. nil for a round paired before the column existed,
    # by hand, by round robin or Keizer (no engine run), or whose trace
    # could not be worked out. Large on a large round, so NOT loaded by
    # default (`load_in_query: false`): a reader asks for it by name.
    # Not cast, not exported.
    field :engine_trace, :map, load_in_query: false

    # The extra points each player was paired with in this round - the
    # virtual points handed to the engine as that round's `XXA` value -
    # `%{"player id" => points}`, non-zero entries only, so `%{}` is "paired
    # on game points alone". Written when a Swiss round is paired
    # (`PairingsEngine.Pairing`) and by the SWAR import (each `[RONDE]`
    # record's `XtraPts`), read back as the history every later round's
    # `XXA` line carries (`Pairing.accelerations/3`). Stored for the same
    # reason `explanation` is: a player's extra points change between
    # rounds (SWAR's "remove half a point"), and the engine needs what each
    # past round was paired WITH, not what the player holds today. Nil for a
    # round paired before the column existed, or by hand. See
    # docs/extra-points.md. Not cast.
    field :virtual_points, :map

    # The Baku virtual points (C.04.7 1.4) this round was paired with,
    # `%{"player id" => points}`, every numbered player (0.0 in Group B) -
    # recorded for the reason `virtual_points` is: the past is not
    # recomputed from today's settings. Nil for a round paired before the column existed, or in a
    # tournament without Baku. Written by `PairingsEngine.Pairing`; not cast.
    field :baku_points, :map

    # A manual pairing alteration in progress on this round (VCL4THP Q65):
    # `%{"before" => [[white, black, bye?], ...]}` - the boards, by player
    # id, as they stood when it began - or nil when none is open. In-flight
    # state, not tournament content: not exported. Written only by
    # `PairingsEngine.ManualPairing`; not cast.
    field :mpa_session, :map

    # The round's MPA PIBE (TEC Manual, "Logging of PIBEs"): the text of the
    # `###` line the TRF carries for it, e.g. `MPA @ Round 5: 1-4 2-3 =>
    # 1-3 2-4`, written when a manual alteration ends with boards that are
    # not the pairing checker's. nil when there is none - at most one per
    # round, and gone with the round. Written only by
    # `PairingsEngine.ManualPairing`; not cast.
    field :mpa_pibe, :string

    # The program that paired this round and its version, e.g. "ainalrami"
    # / "0.48.0" - per round, because a desktop update can change the engine
    # between round 4 and round 5 of one event. Written by the pairing paths
    # that run Ainalrami (`engine_fields/0`); nil for a round paired by hand,
    # by a round-robin table, by Keizer, imported, or paired before the
    # column existed. Exported; cast only by `changeset/2` for the import.
    field :engine, :string
    field :engine_version, :string

    # The engine's pairing proof for this round (`PairingsEngine.PairingProofs`):
    # the gzip file of Ainalrami's JSON Lines proof, one section per pairing
    # group, and the SHA-256 and size of exactly those bytes. Worked out
    # after the round is saved, never inside the click. nil when nobody
    # proved it: proofs switched off, a field too large to prove, a team or
    # non-Swiss round, or a round paired before the column existed. Large,
    # so NOT loaded by default. Not cast.
    field :proof, :binary, load_in_query: false, redact: true
    field :proof_sha256, :string
    field :proof_bytes, :integer

    belongs_to :tournament, PairingsEngine.Tournaments.Tournament
    has_many :pairings, PairingsEngine.Tournaments.Pairing
    # A team round's matches (`PairingsEngine.TeamRoundRobin`); none for an
    # individual round.
    has_many :matches, PairingsEngine.Tournaments.Match
  end

  @doc """
  `query` (all rounds by default) selecting every column but `explanation`
  (and `engine_trace`, which no plain query loads).

  A round's engine account is the largest thing in the database - every
  bracket of a 1,000-player round, as JSON - and every reader that only
  wants the boards and scores was decoding it anyway, once per round per
  load: on a nine-round event most of the time the standings, the pairing
  history and the "Pair round" click spent reading rounds went on JSON
  nobody looked at. The rounds this returns have `explanation: nil`, so
  only a caller that never reads it may use it; one that does uses a plain
  `Round` query, as before.
  """
  def without_explanation(query \\ __MODULE__) do
    fields = __schema__(:query_fields) -- [:explanation]
    Ecto.Query.select(query, [r], struct(r, ^fields))
  end

  @doc """
  The `engine` / `engine_version` a round paired by Ainalrami right now is
  stored with: the engine this running build was compiled against.
  """
  def engine_fields do
    version =
      case Application.spec(:ainalrami, :vsn) do
        nil -> nil
        vsn -> to_string(vsn)
      end

    %{engine: "ainalrami", engine_version: version}
  end

  @doc "The instant to store in `paired_at` for a round paired now."
  def paired_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  def changeset(round, attrs) do
    round
    |> cast(attrs, [
      :number,
      :date,
      :status,
      :published_at,
      :paired_at,
      :explanation,
      :engine,
      :engine_version
    ])
    |> validate_required([:number])
    |> validate_inclusion(:status, ~w(pairing playing finished))
  end
end
