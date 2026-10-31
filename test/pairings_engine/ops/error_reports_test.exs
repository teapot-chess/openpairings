defmodule PairingsEngine.Ops.ErrorReportsTest do
  use PairingsEngine.DataCase, async: false

  alias PairingsEngine.Ops.{ErrorReport, ErrorReports}
  alias PairingsEngine.Ops.ErrorReports.{LoggerHandler, Recorder}

  defp crash(fun) do
    fun.()
  rescue
    e -> {e, __STACKTRACE__}
  end

  describe "from_crash/1 - what is kept out" do
    test "a FunctionClauseError's arguments never reach the stack" do
      secret = "hunter2-password@example.org"
      {e, st} = crash(fn -> apply(String, :to_integer, [%{password: secret}]) end)
      # Make the top frame carry arguments, as a real FunctionClauseError does.
      st = [
        {PairingsEngine.Fake, :login, [secret, %{password: secret}],
         [file: ~c"lib/x.ex", line: 3]}
        | st
      ]

      report = ErrorReports.from_crash({e, st})
      refute report.stacktrace =~ "hunter2"
      refute report.message =~ "hunter2"
      assert report.stacktrace =~ "PairingsEngine.Fake.login/2 (lib/x.ex:3)"
      assert report.location == "PairingsEngine.Fake.login/2"
    end

    test "a MatchError keeps its sentence and loses the term" do
      {e, st} =
        crash(fn -> {:ok, _} = Code.eval_string(~s|{:error, %{email: "a@b.org"}}|) |> elem(0) end)

      report = ErrorReports.from_crash({e, st})
      assert report.kind == "MatchError"
      assert report.message == "no match of right hand side value: [term]"
    end

    test "e-mail addresses and long tokens are scrubbed, and only the first paragraph survives" do
      message =
        ErrorReports.sanitize_message(
          "failed for someone@example.org with key SFMyNTY.g2gDbQAAACRmYWtlLXRva2Vu\n\nApplied changes %{password: \"x\"}"
        )

      assert message == "failed for [email] with key [redacted]"
    end

    test "messages are capped" do
      assert String.length(ErrorReports.sanitize_message(String.duplicate("a b ", 500))) == 300
    end

    test "a 4xx-shaped exception is not a crash" do
      {e, st} = crash(fn -> raise Ecto.NoResultsError, queryable: ErrorReport end)
      assert ErrorReports.from_crash({e, st}) == :ignore
    end

    test "an exit keeps its shape and not its contents" do
      report =
        ErrorReports.from_crash(
          {{:timeout, {GenServer, :call, [:pid, "secret@x.org", 5000]}}, []}
        )

      assert report.kind == "exit"
      assert report.message == "exit: {:timeout, {GenServer, :call, [list]}}"
    end

    test "the same bug on a different line is the same fingerprint" do
      st1 = [{PairingsEngine.A, :f, 1, [file: ~c"lib/a.ex", line: 10]}]
      st2 = [{PairingsEngine.A, :f, 1, [file: ~c"lib/a.ex", line: 99]}]
      a = ErrorReports.from_crash({%RuntimeError{message: "x"}, st1})
      b = ErrorReports.from_crash({%RuntimeError{message: "y"}, st2})
      assert a.fingerprint == b.fingerprint

      refute a.fingerprint ==
               ErrorReports.from_crash({%ArgumentError{message: "x"}, st1}).fingerprint
    end
  end

  describe "record/2" do
    test "dedupes by fingerprint with a count and first/last seen" do
      report = ErrorReports.from_crash({%RuntimeError{message: "boom"}, []})
      t1 = ~U[2026-10-31 10:00:00Z]
      t2 = ~U[2026-10-31 11:00:00Z]

      assert {:new, _} = ErrorReports.record(report, t1)
      assert {:seen, _} = ErrorReports.record(report, t2)

      assert [%ErrorReport{count: 2, first_seen_at: ^t1, last_seen_at: ^t2}] = ErrorReports.list()
    end

    test "keeps at most max_rows, dropping the least recently seen" do
      max = ErrorReports.max_rows()

      for i <- 0..max do
        ErrorReports.record(
          %{fingerprint: "fp#{i}", kind: "k", message: "m", location: nil, stacktrace: ""},
          DateTime.add(~U[2026-10-01 00:00:00Z], i, :minute)
        )
      end

      rows = ErrorReports.list()
      assert length(rows) == max
      refute Enum.any?(rows, &(&1.fingerprint == "fp0"))
    end
  end

  test "the logger handler hands a crash to the recorder, which writes it" do
    name = :"recorder_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Recorder, name: name, alert_email: nil})
    Ecto.Adapters.SQL.Sandbox.allow(PairingsEngine.Repo, self(), pid)

    event = %{
      level: :error,
      msg: {:string, "crash"},
      meta: %{crash_reason: {%RuntimeError{message: "from the handler"}, []}}
    }

    assert :ok = LoggerHandler.log(event, %{config: %{recorder: name}})
    # A plain error line without a crash_reason is not a report.
    assert :ok = LoggerHandler.log(%{event | meta: %{}}, %{config: %{recorder: name}})
    _ = :sys.get_state(pid)

    assert [%ErrorReport{message: "from the handler", kind: "RuntimeError"}] = ErrorReports.list()
  end

  describe "the alert e-mail" do
    import Swoosh.TestAssertions

    # The recorder sends from its own process, not this one.
    setup :set_swoosh_global

    test "a new fingerprint e-mails the operator once, then waits" do
      name = :"recorder_#{System.unique_integer([:positive])}"
      pid = start_supervised!({Recorder, name: name, alert_email: "ops@example.org"})
      Ecto.Adapters.SQL.Sandbox.allow(PairingsEngine.Repo, self(), pid)

      Recorder.capture(name, ErrorReports.from_crash({%RuntimeError{message: "one"}, []}))
      Recorder.capture(name, ErrorReports.from_crash({%ArgumentError{message: "two"}, []}))
      _ = :sys.get_state(pid)

      assert_email_sent(subject: "OpenPairings: new error (RuntimeError)")
      refute_email_sent()
    end
  end
end
