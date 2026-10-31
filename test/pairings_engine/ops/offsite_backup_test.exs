defmodule PairingsEngine.Ops.OffsiteBackupTest do
  use PairingsEngine.DataCase, async: false

  @moduletag :capture_log

  alias PairingsEngine.Ops.{Age, OffsiteBackup, OffsiteBackupRun}

  @required %{
    "OFFSITE_BACKUP_S3_ENDPOINT" => "https://objects.example.test",
    "OFFSITE_BACKUP_S3_BUCKET" => "op-backups",
    "OFFSITE_BACKUP_S3_ACCESS_KEY_ID" => "AKIDEXAMPLE",
    "OFFSITE_BACKUP_S3_SECRET_ACCESS_KEY" => "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
  }

  setup do
    {secret, public} = Age.generate_identity()
    dir = Path.join(System.tmp_dir!(), "offsite-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "openpairings-20261031-120000.opbak")
    File.write!(path, "OPBAK1\n{}\n" <> :crypto.strong_rand_bytes(5_000))
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, config} =
      OffsiteBackup.from_env(
        &Map.get(Map.put(@required, "OFFSITE_BACKUP_RECIPIENTS", public), &1)
      )

    %{secret: secret, public: public, path: path, config: config}
  end

  describe "from_env/1" do
    test "nothing set is disabled, not an error" do
      assert OffsiteBackup.from_env(fn _ -> nil end) == :disabled
    end

    test "half a configuration names what is missing and no value", %{public: public} do
      env = %{
        "OFFSITE_BACKUP_RECIPIENTS" => public,
        "OFFSITE_BACKUP_S3_SECRET_ACCESS_KEY" => "s3cr3t"
      }

      assert {:error, message} = OffsiteBackup.from_env(&Map.get(env, &1))
      assert message =~ "OFFSITE_BACKUP_S3_BUCKET"
      refute message =~ "s3cr3t"
    end

    test "a malformed key, a plain-http remote endpoint and a bad stale value are refused" do
      env = Map.put(@required, "OFFSITE_BACKUP_RECIPIENTS", "age1notakey")

      assert {:error, "OFFSITE_BACKUP_RECIPIENTS entry 1" <> _} =
               OffsiteBackup.from_env(&Map.get(env, &1))

      {_, public} = Age.generate_identity()

      env =
        Map.merge(@required, %{
          "OFFSITE_BACKUP_RECIPIENTS" => public,
          "OFFSITE_BACKUP_S3_ENDPOINT" => "http://far.away"
        })

      assert {:error, "OFFSITE_BACKUP_S3_ENDPOINT" <> _} =
               OffsiteBackup.from_env(&Map.get(env, &1))

      env =
        Map.merge(@required, %{
          "OFFSITE_BACKUP_RECIPIENTS" => public,
          "OFFSITE_BACKUP_STALE_HOURS" => "0"
        })

      assert {:error, "OFFSITE_BACKUP_STALE_HOURS" <> _} =
               OffsiteBackup.from_env(&Map.get(env, &1))
    end

    test "a complete one has defaults", %{config: config} do
      assert config[:stale_hours] == 36
      assert config[:s3][:region] == "us-east-1"
      assert config[:s3][:prefix] == "openpairings"
      assert OffsiteBackup.enabled?(config)
    end
  end

  describe "push/1" do
    test "disabled when not configured" do
      assert OffsiteBackup.push(config: []) == :disabled
      assert OffsiteBackup.status([]) == :disabled
    end

    test "sends a signed PUT of age ciphertext that opens back to the backup", ctx do
      test_pid = self()

      Req.Test.stub(OffsiteBackup, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 10_000_000)

        send(
          test_pid,
          {:put, conn.method, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"),
           body}
        )

        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, "openpairings/openpairings-20261031-120000.opbak.age"} =
               OffsiteBackup.push(config: ctx.config, latest: ctx.path)

      assert_received {:put, "PUT",
                       "/op-backups/openpairings/openpairings-20261031-120000.opbak.age", [auth],
                       body}

      assert "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/" <> _ = auth
      refute body =~ "OPBAK1"
      assert {:ok, plain} = Age.decrypt(body, ctx.secret)
      assert plain == File.read!(ctx.path)

      # The temporary ciphertext is gone, and the same backup is not sent twice.
      refute File.exists?(ctx.path <> ".age.partial")
      assert OffsiteBackup.push(config: ctx.config, latest: ctx.path) == :nothing_new
      assert OffsiteBackup.status(ctx.config) == :ok
    end

    test "a refusal records the S3 error code and nothing else from the reply", ctx do
      Req.Test.stub(OffsiteBackup, fn conn ->
        Plug.Conn.send_resp(conn, 403, """
        <?xml version="1.0"?><Error><Code>SignatureDoesNotMatch</Code>
        <AWSAccessKeyId>AKIDEXAMPLE</AWSAccessKeyId><StringToSign>AWS4-HMAC-SHA256...</StringToSign></Error>
        """)
      end)

      assert {:error, reason} = OffsiteBackup.push(config: ctx.config, latest: ctx.path)
      assert reason == "storage answered HTTP 403 (SignatureDoesNotMatch)"

      assert [%OffsiteBackupRun{status: "failed", error: ^reason}] = OffsiteBackup.runs()
      assert OffsiteBackup.status(ctx.config) == :failing
    end

    test "no local backup is a failure, not a silence", ctx do
      assert {:error, "no local backup to send"} =
               OffsiteBackup.push(config: ctx.config, latest: nil)
    end
  end

  describe "status/2" do
    test "stale when the last success is older than the threshold", ctx do
      Repo.insert!(%OffsiteBackupRun{
        status: "ok",
        object_key: "k",
        started_at: ~U[2026-10-01 00:00:00Z],
        finished_at: ~U[2026-10-01 00:00:00Z]
      })

      assert OffsiteBackup.status(ctx.config, ~U[2026-10-02 11:00:00Z]) == :ok
      assert OffsiteBackup.status(ctx.config, ~U[2026-10-02 12:00:00Z]) == :stale
    end

    test "stale when nothing was ever sent", ctx do
      assert OffsiteBackup.status(ctx.config) == :stale
    end
  end
end
