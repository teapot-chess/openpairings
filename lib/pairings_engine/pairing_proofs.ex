defmodule PairingsEngine.PairingProofs do
  @moduledoc """
  The engine's pairing proof for a round: Ainalrami's certificate that every
  matching it solved while pairing the round was optimal, and that the
  published boards are the pairs it read off them (Ainalrami
  `docs/pairing-proofs.md`; checked with its `tools/verify-proof/verify.exs`,
  which shares no code with the engine).

  ## When

  After the round is saved, inside the round's explanation job
  (`PairingsEngine.ExplanationJobs`), never inside the "Pair round" click: a
  proof pairs the round a second time on the engine's reference path, which
  costs a fraction of a second at 100 players and several seconds at 300.
  The round is paired again from exactly the field and options the click
  used, and the proof is kept only if that pairing is the one the round
  holds - a proof of some other pairing would be worse than none.

  ## Which rounds

  Individual Swiss rounds paired by Ainalrami, one proof section per
  pairing group (a category-paired round has one per category, in one file,
  which is how the engine's own command line writes several rounds). Not
  team rounds, round robins, Keizer or hand pairings: there is no matching
  to prove. Not fields of more than `max_players/0` players in total: the
  reference path's memory grows with the square of the field (1.4 GB at a
  thousand players), and the hosted server has two cores and other
  tournaments to pair. Such a round simply has no proof.

  ## What is kept

  The JSON Lines text, gzipped, with the SHA-256 and size of the gzip bytes
  (`rounds.proof`, `proof_sha256`, `proof_bytes`). Those bytes are what the
  results site serves and what the digest in the snapshot names, so a
  reader can check the file they downloaded is the one this program wrote.

  `config :pairings_engine, :pairing_proofs, false` switches the whole
  thing off (the test suite does, so every pairing in it is not paid for
  twice); `:pairing_proof_max_players` moves the cap.
  """

  import Ecto.Query

  require Logger

  alias PairingsEngine.Repo
  alias PairingsEngine.Tournaments.Round

  @default_max_players 300

  @doc "Whether rounds get proofs at all."
  def enabled?, do: Application.get_env(:pairings_engine, :pairing_proofs, true)

  @doc "The largest field (players, all groups together) that is proved."
  def max_players,
    do: Application.get_env(:pairings_engine, :pairing_proof_max_players, @default_max_players)

  @doc """
  The proof of a round paired from `sections` - the engine runs the click
  kept (`{category, deferred, by_rank}`, `deferred` holding `players`,
  `pairs` and `opts`) - as `{:ok, gzip}`, or `:none` when the round is not
  one that gets a proof, or the second pairing did not reproduce it.
  """
  @spec build(list()) :: {:ok, binary()} | :none
  def build(sections) do
    runs =
      for {_category, %{players: _, pairs: _, opts: _} = deferred, _} <- sections, do: deferred

    players = runs |> Enum.map(&length(&1.players)) |> Enum.sum()

    if enabled?() and runs != [] and players <= max_players() do
      texts = Enum.map(runs, &prove/1)
      if Enum.all?(texts, &is_binary/1), do: {:ok, :zlib.gzip(texts)}, else: :none
    else
      :none
    end
  end

  # One engine run proved: the same field and options, with the proof
  # asked for. The sink is called before `pair_next_round/2` returns, in
  # this process.
  defp prove(run) do
    ref = make_ref()
    expected = run.pairs
    parent = self()
    sink = fn text -> send(parent, {ref, text}) end

    pairs = Ainalrami.Pairing.pair_next_round(run.players, Keyword.put(run.opts, :proof, sink))

    receive do
      {^ref, text} when pairs == expected -> text
      {^ref, _text} -> nil
    after
      0 -> nil
    end
  rescue
    e ->
      Logger.warning("A pairing proof could not be worked out: #{inspect(e.__struct__)}")
      nil
  end

  @doc """
  Stores `gzip` as the proof of round `round_id`, only while the round still
  holds the explanation record `job` was started for - the guard
  `ExplanationJobs.store/3` keeps, so a proof never lands on a round
  unpaired and paired again meanwhile. Returns `:stored` or `:gone`.
  """
  @spec store(integer(), String.t(), binary()) :: :stored | :gone
  def store(round_id, job, gzip) do
    {count, _} =
      Repo.update_all(
        from(r in Round,
          where: r.id == ^round_id and fragment("json_extract(?, '$.job')", r.explanation) == ^job
        ),
        set: [proof: gzip, proof_sha256: digest(gzip), proof_bytes: byte_size(gzip)]
      )

    if count == 1, do: :stored, else: :gone
  end

  @doc "Builds and stores a round's proof; never raises, never fails the job it runs in."
  def run(round_id, job, sections) do
    case build(sections) do
      {:ok, gzip} -> store(round_id, job, gzip)
      :none -> :none
    end
  rescue
    e ->
      Logger.warning("The proof of round #{round_id} was not stored: #{inspect(e.__struct__)}")
      :none
  end

  @doc "The gzip proof of round `round_id`, or nil (the column is not loaded by default)."
  def fetch(round_id) do
    Repo.one(from r in Round, where: r.id == ^round_id, select: r.proof)
  end

  @doc """
  The proof as the snapshot announces it (`rounds[].proof` in OpenResults'
  publish-v1), or nil.
  """
  def announcement(%Round{proof_sha256: sha, proof_bytes: bytes}) when is_binary(sha) do
    %{
      "sha256" => sha,
      "bytes" => bytes,
      "format" => "ainalrami-pairing-proof",
      "compression" => "gzip"
    }
  end

  def announcement(_round), do: nil

  @doc "Lowercase hex SHA-256."
  def digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
