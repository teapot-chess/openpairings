defmodule PairingsEngine.DubovTest do
  @moduledoc """
  A Swiss tournament paired by the Dubov system (C.04.4.1): chosen on the
  tournament, paired by `Ainalrami.Dubov`, out of FIDE mode because the
  program is endorsed for the Dutch system only, written to and read from a
  TRF as `FIDE_DUBOV`, and published as `swiss_variant: "dubov"`.
  """
  use PairingsEngine.DataCase, async: false

  @moduletag :capture_log

  import PairingsEngineWeb.ContractHelpers

  alias PairingsEngine.{Compliance, Pairing, Repo, Snapshot, TrfExport, TrfImport, Tournaments}
  alias PairingsEngine.Tournaments.{Round, Tournament}

  @contract "vendor/openresults/publish-v1"

  setup do
    previous = Application.get_env(:pairings_engine, :explanation_jobs)
    Application.put_env(:pairings_engine, :explanation_jobs, :inline)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:pairings_engine, :explanation_jobs),
        else: Application.put_env(:pairings_engine, :explanation_jobs, previous)
    end)

    :ok
  end

  defp tournament(count, attrs \\ []) do
    t =
      Repo.insert!(
        struct(
          %Tournament{
            name: "Dubov Open",
            type: "swiss",
            swiss_variant: "dubov",
            rounds_count: 5,
            tiebreaks: ~w(BH),
            initial_colour: "white",
            publish_to_openresults: true,
            public_slug: "dubov-#{System.unique_integer([:positive])}",
            round_dates: List.duplicate("2026-10-01", 5)
          },
          attrs
        )
      )

    for n <- 1..count do
      {:ok, _} = Tournaments.create_player(t.id, %{"name" => "P#{n}", "fide_rating" => 2200 - n})
    end

    Tournaments.get_tournament!(t.id)
  end

  defp round(t, number),
    do: Repo.one!(from r in Round, where: r.tournament_id == ^t.id and r.number == ^number)

  test "a Dubov round is paired, records its engine, and has no Dutch account" do
    t = tournament(9)
    assert {:ok, _} = Pairing.pair_next_round(t)

    r1 = round(t, 1) |> Repo.preload(:pairings)
    assert length(r1.pairings) == 5
    assert r1.engine == "ainalrami"
    assert r1.engine_version == to_string(Application.spec(:ainalrami, :vsn))
    assert r1.explanation == nil
    assert r1.proof_sha256 == nil

    # Round 2 is paired from round 1's results by the same system.
    for p <- r1.pairings,
        p.black_player_id,
        do: {:ok, _} = Tournaments.update_pairing_result(p, "1-0")

    assert {:ok, _} = Pairing.pair_next_round(Tournaments.get_tournament!(t.id))
    assert round(t, 2).engine == "ainalrami"
  end

  test "an unrated player is refused by name rather than paired by guesswork" do
    t = tournament(5)
    {:ok, _} = Tournaments.create_player(t.id, %{"name" => "Unrated Newcomer"})

    assert {:error, message} = Pairing.pair_next_round(Tournaments.get_tournament!(t.id))
    assert message =~ "Dubov"
    assert message =~ "Unrated Newcomer"
  end

  test "it leaves FIDE mode, and the Dutch system is FIDE mode again" do
    t = tournament(4)
    refute Compliance.fide_mode?(t)
    assert [%{code: :swiss_system_not_endorsed, restore_to: ["dutch"]}] = Compliance.check(t)

    assert Compliance.fide_mode?(%{t | swiss_variant: "dutch"})
    # A team Swiss pairs by C.04.6, whatever the field says.
    refute Tournament.dubov?(%{t | type: "team-swiss"})
  end

  test "the match format does not go with it" do
    changeset =
      Tournament.changeset(%Tournament{}, %{
        "name" => "X",
        "type" => "swiss",
        "rounds_count" => 4,
        "swiss_variant" => "dubov",
        "swiss_match_format" => true
      })

    assert {_, _} = changeset.errors[:swiss_variant]

    refute Tournament.changeset(%Tournament{}, %{"swiss_variant" => "burstein"}).valid?
  end

  test "the TRF says FIDE_DUBOV, Baku says FIDE_DUBOV_BAKU, and both read back" do
    t = tournament(6)
    {:ok, _} = Pairing.pair_next_round(t)
    {:ok, trf} = TrfExport.export(Tournaments.get_tournament!(t.id))
    assert trf =~ ~r/^192 FIDE_DUBOV\s*$/m

    {:ok, copy, _report} = TrfImport.import_with_report(trf, nil)
    assert copy.swiss_variant == "dubov"
    assert copy.pairing_system == "swiss"

    baku = tournament(6, acceleration: "baku")
    {:ok, _} = Pairing.pair_next_round(baku)
    {:ok, trf} = TrfExport.export(Tournaments.get_tournament!(baku.id))
    assert trf =~ ~r/^192 FIDE_DUBOV_BAKU\s*$/m

    {:ok, copy, _report} = TrfImport.import_with_report(trf, nil)
    assert copy.swiss_variant == "dubov"
    assert copy.acceleration == "baku"
  end

  test "a Dutch tournament still writes the Dutch code" do
    t = tournament(4, swiss_variant: "dutch")
    {:ok, trf} = TrfExport.export(t)
    assert trf =~ ~r/^192 FIDE_DUTCH_2025\s*$/m
  end

  test "the snapshot names the system, and is a valid request" do
    t = tournament(6)
    {:ok, _} = Pairing.pair_next_round(t)
    Tournaments.publish_round_now(round(t, 1))

    snapshot = Snapshot.build(Tournaments.get_tournament!(t.id))
    assert_valid!(@contract, "snapshot.request.schema.json", snapshot)
    assert snapshot["tournament"]["swiss_variant"] == "dubov"
    assert [%{"engine" => %{"name" => "ainalrami"}} = row] = snapshot["rounds"]
    refute Map.has_key?(row, "proof")
  end
end
