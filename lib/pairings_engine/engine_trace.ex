defmodule PairingsEngine.EngineTrace do
  @moduledoc """
  Ainalrami's own account of how it paired a round - what its command line
  prints at the normal level (`Ainalrami.Log`), the reasoning an arbiter
  reads - captured for the ITDX file (`PairingsEngine.ItdxTrace`) and kept
  on `rounds.engine_trace`. Write-only, like the rest of that file's `OP`
  block: nothing reads it back, and it never takes part in a pairing.

  ## Why the command line, and why after the round

  The engine's library calls (`Ainalrami.Pairing.pair_next_round/2` and
  friends, which is what this app pairs with) print nothing at any level:
  the trace is the command line's (`Ainalrami.CLI`), which loads a file,
  pairs it and says what it did. So the trace of an individual Swiss round
  is that program run on the very field the engine paired in the click -
  the parsed players and the options, kept in memory for the round's
  account - written out as the engine's own file (`XXO` records carrying
  the organiser's wishes, exclusions and bye preferences), paired with
  `-p` (the phases, the roster summary, the boards with colours) and
  explained with `-x` (the float cascade, every bracket and the criteria
  that scored).

  That is a second run of the engine, so it happens in the round's account
  job (`PairingsEngine.ExplanationJobs`), after the round is saved, never
  in the "Pair round" click. Measured on a 450-player field (rounds 2 and
  5 of nine): the trace took 65-80 ms against 15-20 ms for the pairing
  itself, about 20 KB a round,
  so it would have been cheap enough for the click - but it would still
  have been a second run, and the click is no place to learn whether a
  second run agrees with the first. So each section records whether the
  boards the trace ends with are the ones that were stored (`"matches"`),
  and the ITDX file says "re-derived" either way and says so loudly when
  they differ.

  A team Swiss is different: `Ainalrami.TeamCLI` renders the result the
  engine already returned (`report/1` and `render_explanation/1`), with no
  second run, so it is captured in the click from the result in hand.

  ## What is kept

  The roster lines (`#3 Name (2100) - 2.0 pts`) are dropped: they restate
  the TRF's `001` records and carry names, which the `OP` block leaves to
  those records. Everything else is kept as printed. What the engine sends
  to stderr (its warnings - organiser deviations, bye preferences it could
  not honour) is not in the trace - stderr is the node's, not the
  process's, so they land in the server's log - and the `OP` block's
  deviation lines and the round's account say the same.

  A section's text is capped at `max_bytes/0`; past it the trace is cut and
  says so.
  """

  require Logger

  @max_bytes 512 * 1024
  @version 1

  @doc """
  Whether individual Swiss rounds are traced (`config :pairings_engine,
  :engine_trace`, on unless set `false` - the test suite does, for speed;
  the trace's own tests switch it back on). A team round is always traced:
  that is rendering a result already in hand.
  """
  def enabled?, do: Application.get_env(:pairings_engine, :engine_trace, true) != false

  @doc "The most text one section keeps."
  def max_bytes, do: @max_bytes

  @doc """
  The trace of an individual Swiss round from its sections as
  `PairingsEngine.Pairing` paired them: `[{category | nil, deferred,
  by_rank}]`, `deferred` the field the engine paired (`:players`, `:pairs`,
  `:engine_tournament`, `:engine_opts`, `:bye_preferences`) and `by_rank`
  local rank -> player. nil when no section could be traced.
  """
  def individual(sections) when is_list(sections) do
    if enabled?(), do: trace_sections(sections)
  end

  defp trace_sections(sections) do
    traced =
      for {category, %{} = deferred, by_rank} <- sections,
          section = individual_section(deferred),
          section != nil do
        Map.merge(section, %{"category" => category, "ranks" => rank_map(by_rank)})
      end

    if traced == [],
      do: nil,
      else: %{"version" => @version, "kind" => "individual", "sections" => traced}
  end

  defp individual_section(deferred) do
    dir = Path.join(System.tmp_dir!(), "engine-trace-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    input = Path.join(dir, "round.trf")
    output = Path.join(dir, "pairs.txt")

    try do
      File.write!(input, engine_file(deferred))

      {code_p, paired} = capture(fn -> Ainalrami.CLI.run([input, "-p", output]) end)
      {_code_x, explained} = capture(fn -> Ainalrami.CLI.run([input, "-x"]) end)

      cli_pairs = if code_p == 0, do: read_pairs(output), else: nil
      stored = Enum.map(deferred.pairs, fn {w, b} -> {w, b || 0} end)

      text =
        (lines(paired, dir) ++ explanation_lines(explained, dir))
        |> squeeze_blank_lines()
        |> Enum.join("\n")
        |> String.trim()
        |> cap()

      %{
        "text" => text,
        "matches" => cli_pairs != nil and Enum.sort(cli_pairs) == Enum.sort(stored),
        "rederived" => true
      }
    rescue
      e ->
        Logger.warning("The engine's trace could not be worked out: #{inspect(e.__struct__)}")
        nil
    after
      File.rm_rf(dir)
    end
  end

  # The field as the engine's own file: the parsed tournament and players
  # the click paired, with the options that rode beside the TRF (the point
  # system, the organiser's soft pairs, bye exclusions and preferences)
  # written in as `BB*` and `XXO` records, which the command line reads back
  # into the same options.
  defp engine_file(deferred) do
    opts = Map.get(deferred, :engine_opts) || []

    tournament =
      (Map.get(deferred, :engine_tournament) || %{})
      |> put_present(:point_system, opts[:point_system])
      |> put_present(:soft_pairs, opts[:soft_pairs])
      |> then(fn t ->
        if (opts[:soft_pairs] || []) != [],
          do: Map.put(t, :soft_position, opts[:soft_position] || :strong),
          else: t
      end)
      |> put_present(:bye_exclusions, opts[:bye_exclusions])
      |> put_present(:bye_preferences, Map.get(deferred, :bye_preferences))

    Ainalrami.Trf.serialize(%{tournament: tournament, players: deferred.players})
  end

  defp put_present(map, _key, value) when value in [nil, []], do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp read_pairs(path) do
    case File.read(path) do
      {:ok, text} ->
        text
        |> String.split(["\r\n", "\n"], trim: true)
        |> Enum.drop(1)
        |> Enum.map(fn line ->
          [w, b] = line |> String.split(" ", trim: true) |> Enum.map(&String.to_integer/1)
          {w, b}
        end)

      _ ->
        nil
    end
  end

  # `-p`'s output without the roster, the temp files named by their names
  # alone (`round.trf`, `pairs.txt`) rather than where they were.
  defp lines(output, dir) do
    output
    |> String.replace([dir <> "/", dir <> "\\"], "")
    |> String.split(["\r\n", "\n"])
    |> Enum.reject(&roster_line?/1)
  end

  # One blank line where the program printed several.
  defp squeeze_blank_lines(lines) do
    lines
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reduce([], fn
      "", ["" | _] = acc -> acc
      line, acc -> [line | acc]
    end)
    |> Enum.reverse()
  end

  # `-x`'s output from where it starts explaining: everything before it
  # repeats `-p`'s.
  defp explanation_lines(output, dir) do
    all = lines(output, dir)

    case Enum.split_while(all, &(not Regex.match?(~r/^\s+explaining round \d+\s*$/, &1))) do
      {_before, [_explaining | rest]} -> rest
      {all, []} -> all
    end
  end

  defp roster_line?(line),
    do: Regex.match?(~r/^\s+#\d+ .* \((?:unrated|\d+)\) - -?[\d.]+ pts\s*$/, line)

  defp cap(text) when byte_size(text) <= @max_bytes, do: text

  defp cap(text) do
    cut = binary_part(text, 0, @max_bytes)
    # Back to a line end, so no character is cut in half.
    cut = cut |> String.split("\n") |> Enum.drop(-1) |> Enum.join("\n")
    cut <> "\n[trace cut at #{@max_bytes} bytes]"
  end

  # Local engine rank -> pairing number, only when they differ (a category
  # paired on its own, a field with gaps in its numbers): the ITDX file's
  # `001` records are by pairing number.
  defp rank_map(by_rank) when is_map(by_rank) do
    pairs =
      for {rank, player} <- by_rank,
          tpn = Map.get(player, :pairing_number),
          is_integer(rank),
          into: %{},
          do: {Integer.to_string(rank), tpn}

    if Enum.all?(pairs, fn {rank, tpn} -> rank == Integer.to_string(tpn) end),
      do: nil,
      else: pairs
  end

  defp rank_map(_by_rank), do: nil

  @doc """
  The trace of a team Swiss round from what `Ainalrami.TeamPairing.pair_round/2`
  returned (with `explain: true`), the teams it was given and the options:
  `Ainalrami.TeamCLI`'s `-p` report and `-x` account of that very result.
  nil when it cannot be rendered.
  """
  def team(result, engine_teams, opts) do
    round = %{
      system: :swiss,
      settings: %{
        score_mode: Keyword.get(opts, :score_mode, :match_points),
        use_secondary?: Keyword.get(opts, :use_secondary?, true),
        type: Keyword.get(opts, :type, :a),
        code: nil,
        unlisted_code: nil
      },
      round: Keyword.get(opts, :round),
      expected_rounds: Keyword.get(opts, :expected_rounds),
      initial_colour: {Keyword.get(opts, :initial_colour), :file},
      field: Enum.map(engine_teams, & &1.tpn),
      out: [],
      absent: Keyword.get(opts, :absent, []),
      teams: engine_teams,
      matches: Enum.map(result.pairs, &{&1.white, &1.black}),
      bye: result.bye,
      keep_apart: Keyword.take(opts, [:forbidden_pairs, :soft_pairs]),
      result: result
    }

    {_ok, text} =
      capture(fn ->
        Ainalrami.Log.step("Pairing engine")
        Ainalrami.TeamCLI.report(round)

        if Map.get(result, :explanation),
          do: IO.write(Ainalrami.TeamCLI.render_explanation(round))

        :ok
      end)

    text =
      text
      |> String.replace(" (no 192: the C.04.6 defaults)", " (the tournament's settings)")
      |> String.replace(" (152)", "")
      |> String.trim()
      |> cap()

    %{
      "version" => @version,
      "kind" => "team",
      "sections" => [%{"category" => nil, "text" => text, "rederived" => false}]
    }
  rescue
    e ->
      Logger.warning("The engine's team trace could not be rendered: #{inspect(e.__struct__)}")
      nil
  end

  @doc """
  Runs `fun` in a process of its own whose standard output is captured, at
  Ainalrami's normal level - the level is per process, so the caller's is
  untouched. `{fun's result, the text}`. A raise in `fun` is caught there
  and comes back as `{:raised, exception}`, so it never takes the caller
  down with it.
  """
  def capture(fun) when is_function(fun, 0) do
    {:ok, io} = StringIO.open("")

    result =
      Task.async(fn ->
        Process.group_leader(self(), io)
        Ainalrami.Log.set_level(:normal)

        try do
          fun.()
        rescue
          e -> {:raised, e}
        catch
          kind, reason -> {:raised, {kind, reason}}
        end
      end)
      |> Task.await(:infinity)

    {:ok, {_input, output}} = StringIO.close(io)
    {result, output}
  end
end
