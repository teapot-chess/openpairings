defmodule PairingsEngine.PairingProofsTest do
  @moduledoc """
  A Swiss round paired by Ainalrami is stored with the engine and version
  that paired it, and - after the round is saved - with the engine's
  pairing proof, which then travels in the snapshot (by digest), in the
  downloaded backup and in the ITDX file.

  Switches the proof setting and the job mode, so `async: false`.
  """
  use PairingsEngine.DataCase, async: false

  @moduletag :capture_log

  import PairingsEngineWeb.ContractHelpers

  alias PairingsEngine.{
    ItdxNotes,
    Pairing,
    PairingProofs,
    Repo,
    Snapshot,
    TournamentExport,
    Tournaments
  }

  alias PairingsEngine.Tournaments.{Round, Tournament}

  @contract "vendor/openresults/publish-v1"

  setup do
    previous =
      for key <- [:pairing_proofs, :pairing_proof_max_players, :explanation_jobs],
          do: {key, Application.get_env(:pairings_engine, key)}

    Application.put_env(:pairings_engine, :pairing_proofs, true)
    Application.put_env(:pairings_engine, :explanation_jobs, :inline)

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:pairings_engine, key),
          else: Application.put_env(:pairings_engine, key, value)
      end
    end)

    :ok
  end

  defp tournament(count) do
    t =
      Repo.insert!(%Tournament{
        name: "Proof Open",
        type: "swiss",
        rounds_count: 5,
        tiebreaks: ~w(BH),
        initial_colour: "white",
        publish_to_openresults: true,
        public_slug: "proof-#{System.unique_integer([:positive])}",
        round_dates: List.duplicate("2026-10-01", 5)
      })

    for n <- 1..count do
      {:ok, _} = Tournaments.create_player(t.id, %{"name" => "P#{n}", "fide_rating" => 2200 - n})
    end

    Tournaments.get_tournament!(t.id)
  end

  defp paired_round(count) do
    t = tournament(count)
    assert {:ok, _} = Pairing.pair_next_round(t)
    round = Repo.one!(from r in Round, where: r.tournament_id == ^t.id and r.number == 1)
    {Tournaments.get_tournament!(t.id), round}
  end

  test "the round says which engine paired it, and carries a proof of it" do
    {_t, round} = paired_round(9)

    assert round.engine == "ainalrami"
    assert round.engine_version == to_string(Application.spec(:ainalrami, :vsn))

    gzip = PairingProofs.fetch(round.id)
    assert is_binary(gzip)
    assert round.proof_sha256 == PairingProofs.digest(gzip)
    assert round.proof_bytes == byte_size(gzip)

    [first | _] = gzip |> :zlib.gunzip() |> String.split("\n", trim: true)
    assert %{"type" => "round", "format" => "ainalrami-pairing-proof"} = Jason.decode!(first)
  end

  test "the proof is not loaded with the round, nor by the plain readers" do
    {_t, round} = paired_round(6)
    assert round.proof_sha256
    assert round.proof == nil
  end

  test "switched off, or a field above the cap: the engine is recorded, no proof" do
    Application.put_env(:pairings_engine, :pairing_proofs, false)
    {_t, off} = paired_round(6)
    assert off.engine == "ainalrami"
    assert off.proof_sha256 == nil

    Application.put_env(:pairings_engine, :pairing_proofs, true)
    Application.put_env(:pairings_engine, :pairing_proof_max_players, 5)
    {_t, big} = paired_round(6)
    assert big.engine == "ainalrami"
    assert big.proof_sha256 == nil
  end

  test "the snapshot names the engine and the proof by digest, and is a valid request" do
    {t, round} = paired_round(8)
    Tournaments.publish_round_now(round)
    snapshot = Snapshot.build(Tournaments.get_tournament!(t.id))

    assert_valid!(@contract, "snapshot.request.schema.json", snapshot)
    assert snapshot["tournament"]["swiss_variant"] == "dutch"

    [row] = snapshot["rounds"]
    assert row["engine"] == %{"name" => "ainalrami", "version" => round.engine_version}
    assert row["proof"]["sha256"] == round.proof_sha256
    assert row["proof"]["bytes"] == round.proof_bytes
    refute Map.has_key?(row["proof"], "gzip_base64")
  end

  test "the backup carries the proof when asked, and the import keeps it only if it is intact" do
    {t, round} = paired_round(7)

    plain = TournamentExport.export_tournament(t)
    [plain_round] = hd(plain["tournaments"])["rounds"]
    assert plain_round["engine"] == "ainalrami"
    refute Map.has_key?(plain_round, "proof")

    envelope = TournamentExport.export_tournament(t, include_proofs: true)
    [exported] = hd(envelope["tournaments"])["rounds"]
    assert exported["proof"]["sha256"] == round.proof_sha256

    scope = PairingsEngine.AccountsFixtures.user_scope_fixture()
    {:ok, [copy]} = PairingsEngine.TournamentImport.import(envelope, scope)
    restored = Repo.one!(from r in Round, where: r.tournament_id == ^copy.id)
    assert restored.engine == "ainalrami"
    assert restored.proof_sha256 == round.proof_sha256
    assert PairingProofs.fetch(restored.id) == PairingProofs.fetch(round.id)

    tampered =
      update_in(envelope, ["tournaments", Access.at(0), "rounds", Access.at(0), "proof"], fn p ->
        Map.put(p, "gzip_base64", Base.encode64(:zlib.gzip("not a proof")))
      end)

    {:ok, [other]} = PairingsEngine.TournamentImport.import(tampered, scope)
    assert Repo.one!(from r in Round, where: r.tournament_id == ^other.id).proof_sha256 == nil
  end

  test "the ITDX file's round line names the engine and the proof" do
    {t, round} = paired_round(6)
    [line] = ItdxNotes.lines(t, [1]) |> Enum.filter(&String.starts_with?(&1, "OP round 1"))
    assert line =~ "engine ainalrami #{round.engine_version}"
    assert line =~ "proof sha256 #{round.proof_sha256}"
  end
end
