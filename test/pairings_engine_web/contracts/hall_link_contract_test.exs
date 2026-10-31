defmodule PairingsEngineWeb.HallLinkContractTest do
  @moduledoc """
  `priv/contracts/hall-link-v1/`, from OpenPairings' side.

  The line itself is the hall plugins' (`openpairings_nunki`,
  `openpairings_polis`), built into the hosted edition from the Nunki and
  Polis repositories, and held to these files there, in their own CI. What
  is left here: the files are whole and agree with themselves, and the one
  pairing link the core makes - Manubrium's - is the contract's, with the
  contract's code and the contract's fifteen minutes.
  """
  use PairingsEngine.DataCase, async: false

  import PairingsEngine.AccountsFixtures
  import PairingsEngineWeb.ContractHelpers

  alias PairingsEngine.{Manubrium, RateLimit}

  @contract "hall-link-v1"

  describe "the contract's files" do
    test "index.json lists exactly what is there" do
      assert_index!(@contract)
    end

    test "every example is valid against its schema, and every message has one" do
      examples = examples(@contract)

      for {file, schema, data} <- examples do
        assert File.exists?(Path.join(dir(@contract), schema)), "#{file}: no #{schema}"
        assert_valid!(@contract, schema, data)
      end

      covered = MapSet.new(examples, &elem(&1, 1))

      for schema <- files(@contract),
          String.ends_with?(schema, ".schema.json"),
          schema != "common.schema.json",
          do: assert(schema in covered, "#{schema} has no example")
    end

    test "a $ref into common.schema.json is followed" do
      # A refusal reason nobody sends fails through the reference to
      # nothing, and a key too short to be one fails through common's.
      refute valid?(@contract, "server-refused.schema.json", %{type: "refused", reason: "bored"})

      refute valid?(@contract, "device-hello.schema.json", %{
               type: "hello",
               v: 1,
               device: "d",
               key: "short",
               name: "",
               software: ""
             })
    end

    test "the README says what the pairing code is" do
      readme = dir(@contract) |> Path.join("README.md") |> File.read!()
      assert readme =~ "15\n  minutes"
      assert readme =~ "43 characters"
    end
  end

  describe "Manubrium's pairing link" do
    setup do
      RateLimit.clear_all()
      %{scope: user_scope_fixture()}
    end

    test "is built the way the examples are" do
      for {"examples/pairing-link." <> _ = file, _schema, %{"app" => "manubrium"} = ex} <-
            examples(@contract) do
        assert Manubrium.connect_link(ex["server"], ex["code"]) == ex["link"], file
      end
    end

    test "carries a code of the contract's shape, good for fifteen minutes", %{scope: scope} do
      server = "https://pairings.example"

      {:ok, %{secret: secret, link: link, expires_at: expires_at}} =
        Manubrium.create_connect_code(scope, server)

      assert_valid!(@contract, "pairing-link.schema.json", %{
        app: "manubrium",
        link: link,
        server: server,
        code: secret
      })

      assert secret =~ ~r/\A[A-Za-z0-9_-]{43}\z/
      assert Manubrium.connect_ttl_minutes() == 15
      assert DateTime.diff(expires_at, DateTime.utc_now()) in 840..900
    end
  end
end
