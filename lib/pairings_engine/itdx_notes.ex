defmodule PairingsEngine.ItdxNotes do
  @moduledoc """
  The OpenPairings block of an ITDX file (`TrfExport.export/3` with
  `itdx: true`): `###` comment lines for everything the app knows about an
  event that TRF26's records cannot say - the settings it was paired with,
  the rules and byes in force, when each round was paired and what was done
  to it by hand.

  Write-only. The block is exported data for whoever receives the file;
  nothing in this app reads it back and nothing in it ever influences a
  pairing. (The `Unplayed @` line that the importer does read belongs to
  `TrfExport`, not to this block.)

  Plain ASCII, English, one fact per line, every line starting `OP `. No
  personal data beyond what the TRF records already hold: players appear as
  starting ranks, and no e-mail address, key, token or address is written.
  The one piece of free text is the reason an arbiter gave for a hand edit
  (`HandReason`), written next to that edit with accents stripped, control
  characters and line breaks gone and the length capped. Left out on
  purpose: the rest of what audit rows carry (player names, summaries), so
  only their kind, round and time are used; the engine's per-board pairing
  explanation is not summarised here.
  """

  import Ecto.Query, only: [from: 2]

  alias PairingsEngine.{Audit, Repo, Tournaments}
  alias PairingsEngine.Tournaments.Tournament

  # Settings worth passing on, in the order they are written. Only plain
  # values: nothing that names a person, a place or a key.
  @settings ~w(type pairing_system rounds_count points_win points_draw points_loss bye_value
               presence_value abs_value abs_jusque abs_nbfois absent_counts_as_vur
               late_entry_absences ask_bye_type presence_on_allocated_bye tiebreak_unrated_rating
               tiebreak_unrated_method chess960 long_event shared_places acceleration standard
               rate_of_play initial_colour initial_colour_drawn rating_method
               initial_order_tiebreak late_entry_numbering round_one_absentees_late soft_position
               extra_points_mode count_extra_points pair_by_category categories_enabled
               rr_cycles rr_match_format rr_reverse_last_two keizer_top_value swiss_match_format
               postponed_games postponed_requester_outcome postponed_opponent_outcome
               fide_compliance_lost_round baku_group_a_last
               team_boards team_match_points_win team_match_points_draw team_match_points_loss
               team_board_colours team_pab_match_points team_pab_game_points
               team_withdrawal_annul team_forfeit_board_points team_lineups team_board_order
               team_rating_method team_unrated_rating team_primary_score team_tpn_until_round
               team_pairing_mode)a

  @audit_actions Enum.uniq(
                   ~w(pairing.round_paired pairing.mpa_started pairing.mpa_finished
                      pairing.result_changed pairing.result_cleared pairing.players_swapped
                      pairing.player_substituted pairing.rounds_swapped pairing.round_deleted) ++
                     PairingsEngine.HandReason.actions()
                 )

  @doc """
  The block for `tournament`, limited to `rounds`, as the lines (without
  their `### `) `TrfExport.mark_copy/2` puts in the file.
  """
  def lines(%Tournament{} = tournament, rounds) when is_list(rounds) do
    tpn = tpns(tournament.id)

    (header() ++
       setting_lines(tournament) ++
       rule_lines(tournament, tpn) ++
       round_lines(tournament, rounds) ++
       audit_lines(tournament, rounds, paired_rounds(tournament, rounds)) ++
       player_lines(tournament, rounds, tpn))
    |> Enum.map(&ascii/1)
  end

  defp header do
    [
      "OP block: written by OpenPairings #{vsn(:pairings_engine)} " <>
        "(Ainalrami #{vsn(:ainalrami)}); informational only, not read back"
    ]
  end

  defp vsn(app) do
    case Application.spec(app, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end

  defp setting_lines(t) do
    scalars =
      @settings
      |> Enum.reject(&(not Tournament.team?(t) and String.starts_with?(to_string(&1), "team_")))
      |> Enum.flat_map(fn key ->
        case Map.get(t, key) do
          v when v in [nil, ""] -> []
          v -> ["OP setting #{key}: #{value(v)}"]
        end
      end)

    tiebreaks =
      case t.tiebreaks do
        [_ | _] = list -> ["OP setting tiebreaks: " <> Enum.join(list, " ")]
        _ -> []
      end

    scalars ++ tiebreaks
  end

  # Prohibitions and wishes by starting rank. Rule names (clubs, federations)
  # are rule kinds, not people; they are written as stored.
  defp rule_lines(t, tpn) do
    pairs =
      for f <- Tournaments.list_forbidden_pairings(t.id) |> Enum.reverse() do
        "OP prohibition pair #{rank(tpn, f.player_a_id)}-#{rank(tpn, f.player_b_id)}" <>
          if(f.soft, do: " soft", else: "") <>
          if(f.from_round, do: " from round #{f.from_round}", else: "")
      end

    rules =
      for r <- Tournaments.list_pairing_rules(t.id) do
        who =
          cond do
            r.player_ids != [] -> " players " <> Enum.map_join(r.player_ids, "-", &rank(tpn, &1))
            r.team_ids != [] -> " teams " <> Enum.join(r.team_ids, "-")
            true -> ""
          end

        "OP prohibition rule #{r.kind}#{who}" <>
          if(r.soft, do: " soft", else: "") <>
          " window #{r.window}" <>
          if(r.from_round, do: " from round #{r.from_round}", else: "")
      end

    pairs ++ rules
  end

  defp round_lines(t, rounds) do
    query =
      from r in PairingsEngine.Tournaments.Round,
        where: r.tournament_id == ^t.id and r.number in ^rounds,
        order_by: r.number

    for r <- query |> PairingsEngine.Tournaments.Round.without_explanation() |> Repo.all() do
      "OP round #{r.number}: status #{r.status}" <>
        if(r.date not in [nil, ""], do: ", date #{r.date}", else: "") <>
        if(r.paired_at, do: ", paired #{stamp(r.paired_at)}", else: "") <>
        if(r.mpa_pibe, do: ", hand-edited (see the MPA line)", else: "")
    end
  end

  # The rounds (of `rounds`) that carry their own pairing time. The round
  # line says when those were paired, so their `pairing.round_paired` audit
  # rows are not repeated; a round without one (an old round, an imported
  # one) keeps the audit row's time as the fallback.
  defp paired_rounds(t, rounds) do
    Repo.all(
      from r in PairingsEngine.Tournaments.Round,
        where: r.tournament_id == ^t.id and r.number in ^rounds and not is_nil(r.paired_at),
        select: r.number
    )
  end

  # What was done to each round by hand, and when a round without a pairing
  # time of its own was paired, from the audit trail's kind, round and time -
  # and, for a hand edit, the reason the arbiter gave.
  defp audit_lines(t, rounds, stamped) do
    t.id
    |> Audit.list_for_tournament(actions: @audit_actions, limit: 500)
    |> Enum.reverse()
    |> Enum.flat_map(fn row ->
      round = row.details["round"]

      cond do
        not (is_integer(round) and round in rounds) ->
          []

        row.action == "pairing.round_paired" and round in stamped ->
          []

        true ->
          [
            "OP event #{stamp(row.inserted_at)} round #{round}: #{row.action}#{counts(row)}#{reason(row)}"
          ]
      end
    end)
  end

  defp reason(%{details: %{"reason" => text}}) when is_binary(text) do
    case PairingsEngine.HandReason.ascii(text) do
      "" -> ""
      ascii -> ~s( reason "#{String.replace(ascii, ~s("), "'")}")
    end
  end

  defp reason(_row), do: ""

  defp counts(%{action: "pairing.round_paired", details: d}) do
    parts =
      for {key, label} <- [
            {"board_count", "boards"},
            {"bye_count", "byes"},
            {"floater_count", "floaters"},
            {"rematch_count", "rematches"}
          ],
          is_integer(d[key]),
          do: "#{label} #{d[key]}"

    if parts == [], do: "", else: " (" <> Enum.join(parts, ", ") <> ")"
  end

  defp counts(_row), do: ""

  # Per player, by starting rank: only what departs from the default.
  defp player_lines(t, rounds, tpn) do
    players =
      for p <- Tournaments.list_players(t.id), p.pairing_number != nil do
        facts =
          [
            p.status not in [nil, "", "active"] && "status #{p.status}",
            p.start_round > 1 && "late entry, first round #{p.start_round}",
            p.absent && "absent",
            p.forfeit && "withdrawn",
            p.absent_rounds not in [nil, ""] && "absent in rounds #{p.absent_rounds}",
            p.no_bye &&
              "no allocated bye" <>
                if(p.no_bye_rounds in [nil, ""], do: "", else: " in rounds #{p.no_bye_rounds}"),
            p.bye_preference not in [nil, ""] &&
              "bye preference #{p.bye_preference}" <>
                if(p.bye_preference_rounds in [nil, ""],
                  do: "",
                  else: " in rounds #{p.bye_preference_rounds}"
                ),
            p.no_half_bye && "no half-point bye",
            (is_number(p.extra_points) and p.extra_points != 0) &&
              "extra points #{value(p.extra_points)}"
          ]
          |> Enum.filter(& &1)

        {p.pairing_number, facts}
      end
      |> Enum.reject(fn {_rank, facts} -> facts == [] end)
      |> Enum.sort()
      |> Enum.map(fn {rank, facts} -> "OP player #{rank}: " <> Enum.join(facts, "; ") end)

    byes =
      for {round, player_id, type} <-
            Repo.all(
              from b in "byes",
                where: b.tournament_id == ^t.id and b.round in ^rounds,
                order_by: [b.round, b.player_id],
                select: {b.round, b.player_id, b.type}
            ) do
        "OP bye round #{round}: player #{rank(tpn, player_id)} #{type}"
      end

    players ++ byes
  end

  defp tpns(tournament_id) do
    Repo.all(
      from p in PairingsEngine.Tournaments.Player,
        where: p.tournament_id == ^tournament_id,
        select: {p.id, p.pairing_number}
    )
    |> Map.new()
  end

  defp rank(tpn, id), do: Map.get(tpn, id) || "?"

  defp stamp(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M") <> " UTC"
  defp stamp(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M") <> " UTC"
  defp stamp(_), do: "unknown time"

  defp value(v) when is_float(v), do: :erlang.float_to_binary(v, [:compact, decimals: 2])
  defp value(v) when is_boolean(v), do: to_string(v)
  defp value(v), do: to_string(v)

  # One line of printable ASCII: a control character becomes a space, so no
  # value can start a second record, and anything beyond ASCII an underscore.
  defp ascii(line) do
    line
    |> String.to_charlist()
    |> Enum.flat_map(fn
      c when c in 32..126 -> [c]
      c when c < 32 -> [32]
      _ -> [?_]
    end)
    |> List.to_string()
  end
end
