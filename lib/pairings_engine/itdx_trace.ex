defmodule PairingsEngine.ItdxTrace do
  @moduledoc """
  The last section of an ITDX file's OpenPairings block: how the engine
  paired each round in the file. `PairingsEngine.ItdxNotes.trace_lines/2`
  is the way in, which keeps every line to the block's rules (ASCII, `OP `
  first); `PairingsEngine.TrfExport` writes them after the last record.

  Per round, the first of these that applies:

    * **trace** - Ainalrami's own output at its normal level, as
      `PairingsEngine.EngineTrace` kept it (`rounds.engine_trace`), one
      `OP trace R<n> | ` line per line it printed. For an individual Swiss
      the trace is re-derived after pairing, from the field the engine was
      given, and the header says whether it ends with the stored boards.
    * **account** - the round's stored engine account (`rounds.explanation`)
      in short: brackets, floats, the criteria that scored, the bye and its
      candidates, the organiser's deviations. For a round paired before
      traces were kept.
    * one line saying there is neither - why, where it can be told (a round
      robin, Keizer, a match's second leg, an account still pending or
      failed), and otherwise that the round was made by hand, imported, or
      paired before any of this was kept.

  When `RoundExplanation.divergence/2` (or the team version) finds boards
  that are no longer the engine's, a line says the round was edited after
  the engine paired it; the edits themselves are the block's event lines.

  Players are starting ranks, as everywhere in the block; names stay in the
  `001` records. A section whose engine numbered its own field (a category
  paired on its own) says which engine rank is which starting rank.
  """

  import Ecto.Query, only: [from: 2]

  alias PairingsEngine.{Repo, RoundExplanation, TeamRoundExplanation, Tournaments}
  alias PairingsEngine.Tournaments.{Round, Tournament}

  @ranks_per_line 20

  @doc "The section for `rounds` of `tournament`, as lines without `### `."
  def lines(%Tournament{} = tournament, rounds) when is_list(rounds) do
    loaded =
      Repo.all(
        from r in Round,
          where: r.tournament_id == ^tournament.id and r.number in ^rounds,
          order_by: r.number,
          select_merge: %{engine_trace: r.engine_trace},
          preload: [:pairings]
      )

    case loaded do
      [] ->
        []

      loaded ->
        tpn = tpns(tournament.id)

        [
          "OP trace: how Ainalrami paired each round - its own output at its normal level " <>
            "where kept, otherwise the stored account; informational only, not read back"
        ] ++ Enum.flat_map(loaded, &round_lines(tournament, &1, tpn))
    end
  end

  defp round_lines(t, %Round{} = round, tpn) do
    n = round.number

    body =
      cond do
        trace?(round.engine_trace) ->
          trace_lines(n, round.engine_trace)

        t.pairing_system == "round_robin" ->
          ["OP trace R#{n}: no engine run - a round robin is paired from the Berger tables"]

        t.pairing_system == "keizer" ->
          ["OP trace R#{n}: no engine run - Keizer rounds are paired by OpenPairings itself"]

        second_leg?(t, round) ->
          [
            "OP trace R#{n}: no engine run - the second leg of a match is the round before " <>
              "with the colours reversed"
          ]

        true ->
          account_lines(n, round.explanation, tpn)
      end

    body ++ divergence_lines(t, round)
  end

  defp trace?(%{"sections" => [_ | _]}), do: true
  defp trace?(_), do: false

  defp second_leg?(%Tournament{swiss_match_format: true}, %Round{number: n, explanation: nil}),
    do: rem(n, 2) == 0

  defp second_leg?(_t, _round), do: false

  ## ---------- the engine's own trace ----------

  defp trace_lines(n, %{"kind" => kind, "sections" => sections}) do
    Enum.flat_map(sections, fn section ->
      label = label(n, section["category"])

      how =
        cond do
          kind == "team" ->
            "engine trace, rendered from the result the engine returned"

          section["matches"] == true ->
            "engine trace, re-derived after pairing from the field the engine paired; " <>
              "ends with the stored boards"

          true ->
            "engine trace, re-derived after pairing from the field the engine paired; " <>
              "DOES NOT end with the stored boards - read it as an approximation"
        end

      ["#{label}: #{how}"] ++
        round_label_lines(label, n, section["text"]) ++
        rank_lines(label, section["ranks"]) ++
        Enum.map(text_lines(section["text"]), &"#{label} | #{&1}")
    end)
  end

  # The command line names the round it pairs by the columns in its file,
  # and a player sitting the round out (an absence, a requested bye,
  # another category) already has one for it - so it can be a number ahead.
  # Said once, rather than left for the reader to puzzle out.
  defp round_label_lines(label, n, text) when is_binary(text) do
    case Regex.run(~r/pairing round (\d+)/, text) do
      [_, m] when m != "" ->
        if String.to_integer(m) == n,
          do: [],
          else: [
            "#{label}: this is round #{n}; the engine counts the column of the players " <>
              "sitting it out as history, so its own lines call it round #{m}"
          ]

      _ ->
        []
    end
  end

  defp round_label_lines(_label, _n, _text), do: []

  defp text_lines(text) when is_binary(text) do
    text
    |> String.replace("·", "-")
    |> String.split(["\r\n", "\n", "\r"])
    |> Enum.map(&String.trim_trailing/1)
  end

  defp text_lines(_), do: []

  defp rank_lines(_label, ranks) when ranks in [nil, %{}], do: []

  defp rank_lines(label, ranks) when is_map(ranks) do
    ranks
    |> Enum.map(fn {rank, tpn} -> {String.to_integer(rank), tpn} end)
    |> Enum.sort()
    |> Enum.map(fn {rank, tpn} -> "#{rank}=#{tpn}" end)
    |> Enum.chunk_every(@ranks_per_line)
    |> Enum.map(&"#{label} ranks (engine rank=starting rank): #{Enum.join(&1, " ")}")
  end

  defp label(n, nil), do: "OP trace R#{n}"

  defp label(n, category),
    do: "OP trace R#{n} [#{PairingsEngine.HandReason.ascii(to_string(category))}]"

  ## ---------- the stored account ----------

  defp account_lines(n, nil, _tpn) do
    [
      "OP trace R#{n}: none stored - the round was made by hand, imported from a file, " <>
        "or paired before OpenPairings kept the engine's account"
    ]
  end

  defp account_lines(n, %{"status" => "pending"}, _tpn),
    do: ["OP trace R#{n}: none stored - the engine's account was still being worked out"]

  defp account_lines(n, %{"status" => "failed"}, _tpn),
    do: ["OP trace R#{n}: none stored - the engine's account could not be worked out"]

  defp account_lines(n, %{"kind" => "team_swiss"} = account, _tpn),
    do: team_account_lines(n, account)

  defp account_lines(n, %{"sections" => sections}, tpn) when is_list(sections) do
    Enum.flat_map(sections, fn section ->
      label = label(n, section["category"])
      r = &rank(tpn, &1)

      ["#{label}: stored account (no engine trace was kept for this round)"] ++
        Enum.map(account_body(section, r), &"#{label} | #{&1}")
    end)
  end

  defp account_lines(n, _other, _tpn),
    do: ["OP trace R#{n}: none stored - the round's account is in a form this file does not show"]

  defp account_body(section, r) do
    brackets =
      (section["brackets"] || [])
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {b, i} ->
        scored =
          for %{"label" => label, "value" => value} <- b["rungs"] || [], value not in [0, nil] do
            "#{label} #{value}"
          end

        [
          "bracket #{i} score #{score(b["group"])}: moved down #{ids(b["mdps"], r)}; " <>
            "residents #{ids(b["residents"], r)}; paired #{boards(b["pairs"], r)}; " <>
            "floats down #{ids(b["floats"], r)}"
        ] ++
          if(scored == [],
            do: [],
            else: ["  criteria that scored: " <> Enum.join(scored, "; ")]
          )
      end)

    brackets ++
      bye_lines(section, r) ++
      deviation_lines(section, r)
  end

  defp bye_lines(section, r) do
    holder = section["bye_holder"] || get_in(section, ["bye", "holder"])

    case {holder, section["bye"]} do
      {nil, _} ->
        []

      {holder, %{"candidates" => [_ | _] = candidates}} ->
        [
          "bye: player #{r.(holder)}; the other candidates: " <>
            Enum.map_join(candidates, ", ", fn c ->
              "#{r.(c["player"])} #{c["outcome"]}" <>
                if(c["reason"], do: " (#{c["reason"]})", else: "")
            end)
        ]

      {holder, _} ->
        ["bye: player #{r.(holder)}"]
    end
  end

  defp deviation_lines(section, r) do
    [
      section["bye_exclusions"] &&
        "organiser's bye exclusions: #{ids(section["bye_exclusions"], r)}",
      section["bye_passed_over"] &&
        "passed over for the bye because of an exclusion: #{ids(section["bye_passed_over"], r)}",
      section["bye_exclusion_lifted"] &&
        "bye exclusion lifted for this round: player #{r.(section["bye_exclusion_lifted"])}",
      section["soft_pairs_moved"] == true &&
        "the organiser's soft pairs changed this round",
      bye_preference_line(section["bye_preference"], r)
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp bye_preference_line(%{} = pref, r) do
    "bye preferences: " <>
      if(pref["moved"] == true, do: "moved the bye", else: "did not move the bye") <>
      if(pref["fide_bye"], do: "; without them player #{r.(pref["fide_bye"])}", else: "") <>
      if(pref["decided_by"], do: "; decided by #{pref["decided_by"]}", else: "")
  end

  defp bye_preference_line(_pref, _r), do: nil

  defp team_account_lines(n, account) do
    label = "OP trace R#{n}"

    bye =
      case account["bye"] do
        %{"tpn" => tpn} -> ["bye: team #{tpn}"]
        _ -> []
      end

    brackets =
      (account["brackets"] || [])
      |> Enum.with_index(1)
      |> Enum.map(fn {b, i} ->
        "bracket #{i} score #{score(b["score"])}: residents #{list(b["residents"])}; " <>
          "upfloaters #{list(b["upfloaters"])}; pairs #{boards(b["pairs"], & &1)}; " <>
          "C8 #{b["c8"]} C9 #{b["c9"]} C10 #{b["c10"]}"
      end)

    colours =
      for p <- account["pairs"] || [] do
        "team #{p["white"]} (white) vs. team #{p["black"]}: first team #{p["first_team"]}" <>
          if(p["first_team_rule"], do: " (#{p["first_team_rule"]})", else: "") <>
          if(p["colour_rule"], do: ", colours by #{p["colour_rule"]}", else: "")
      end

    ["#{label}: stored account (no engine trace was kept for this round)"] ++
      Enum.map(bye ++ brackets ++ colours, &"#{label} | #{&1}")
  end

  ## ---------- edited after pairing ----------

  defp divergence_lines(t, round) do
    changed =
      if Tournament.team_swiss?(t) and match?(%{"kind" => "team_swiss"}, round.explanation) do
        TeamRoundExplanation.divergence(round, Tournaments.list_matches(round.id))
      else
        RoundExplanation.divergence(round)
      end

    case changed do
      {:changed, count} ->
        [
          "OP trace R#{round.number}: the boards were edited after the engine paired the round " <>
            "(#{count} of its pairs no longer on a board); the trace and account describe the " <>
            "engine's round, the edits are the event lines above"
        ]

      _ ->
        []
    end
  end

  ## ---------- helpers ----------

  defp tpns(tournament_id) do
    Repo.all(
      from p in PairingsEngine.Tournaments.Player,
        where: p.tournament_id == ^tournament_id,
        select: {p.id, p.pairing_number}
    )
    |> Map.new()
  end

  defp rank(_tpn, nil), do: "-"
  defp rank(tpn, id), do: Map.get(tpn, id) || "?"

  defp ids(list, r) when is_list(list) and list != [], do: Enum.map_join(list, ",", r)
  defp ids(_list, _r), do: "-"

  defp list(list) when is_list(list) and list != [], do: Enum.join(list, ",")
  defp list(_list), do: "-"

  defp boards(pairs, r) when is_list(pairs) and pairs != [] do
    Enum.map_join(pairs, " ", fn
      [a, b] -> "#{r.(a)}-#{if(b, do: r.(b), else: "bye")}"
      other -> inspect(other)
    end)
  end

  defp boards(_pairs, _r), do: "-"

  defp score(nil), do: "?"
  defp score(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 1)
  defp score(v), do: to_string(v)
end
