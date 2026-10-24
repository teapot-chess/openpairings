defmodule PairingsEngine.TiebreakTableCodesTest do
  @moduledoc """
  FIDE's "Mandatory Tie-Breaks - TRF26" table: every code on it is one an
  arbiter can pick (individual events for the individual half, team events for
  the team half), the code survives the trip through the bridge and a TRF
  `202`/`212` record, and the `/P` variants add up the way Ainalrami says.

  The list is the table as Ainalrami's own test carries it: 151 printed codes,
  158 once the `x` values (Koya limits, SSSC factors) are given two values each.
  """
  # async: false - whole tournaments, and SQLite takes one writer.
  use PairingsEngine.DataCase, async: false

  import ExUnit.CaptureIO
  import PairingsEngine.TeamFixtures

  alias Ainalrami.Tiebreaks.{Code, Event}
  alias PairingsEngine.{Pairing, Repo, Standings, TeamStandings, Tiebreaks, Tournaments}
  alias PairingsEngine.{TrfExport, TrfImport}
  alias PairingsEngine.Standings.AinalramiBridge
  alias PairingsEngine.Tiebreaks.Builder
  alias PairingsEngine.Tournaments.Tournament

  @individual ~w(
    DE DE/P BPG BWG REP SB SB/C1 SB/C2 SB/P SB/C1/P SB/C2/P
    ARO ARO/C1 ARO/C2 ARO/M1 ARO/M2 TPR PTP APRO APPO
    WIN WON PS PS/C1 PS/C2 BH BH/C1 BH/C2 BH/M1 BH/M2
    BH/P BH/C1/P BH/C2/P BH/M1/P BH/M2/P
    FB FB/C1 FB/C2 FB/M1 FB/M2 FB/P FB/C1/P FB/C2/P FB/M1/P FB/M2/P
    AOB AOB/F KS KS/L1 KS/L-2
  )

  @team ~w(
    WIN:MP WON:MP PS:MP PS:GP PS:MP/C1 PS:MP/C2 PS:GP/C1 PS:GP/C2
    BH:MP BH:GP BH:MP/C1 BH:MP/C2 BH:MP/M1 BH:MP/M2 BH:GP/C1 BH:GP/C2 BH:GP/M1 BH:GP/M2
    BH:MP/P BH:GP/P
    BH:MP/C1/P BH:MP/C2/P BH:MP/M1/P BH:MP/M2/P BH:GP/C1/P BH:GP/C2/P BH:GP/M1/P BH:GP/M2/P
    FB:MP FB:GP FB:MP/C1 FB:MP/C2 FB:MP/M1 FB:MP/M2 FB:GP/C1 FB:GP/C2 FB:GP/M1 FB:GP/M2
    FB:MP/P FB:GP/P
    FB:MP/C1/P FB:MP/C2/P FB:MP/M1/P FB:MP/M2/P FB:GP/C1/P FB:GP/C2/P FB:GP/M1/P FB:GP/M2/P
    AOB:MP AOB:GP AOB:MP/F AOB:GP/F
    KS:MP KS:MP/L1 KS:MP/L-2 KS:GP KS:GP/L1 KS:GP/L-2
    BC TBR BBE MPvGP
    EMMSB EMMSB/C1 EMMSB/C2 EMMSB/P EMMSB/C1/P EMMSB/C2/P
    EMGSB EMGSB/C1 EMGSB/C2 EMGSB/P EMGSB/C1/P EMGSB/C2/P
    EGMSB EGMSB/C1 EGMSB/C2 EGMSB/P EGMSB/C1/P EGMSB/C2/P
    EGGSB EGGSB/C1 EGGSB/C2 EGGSB/P EGGSB/C1/P EGGSB/C2/P
    EDE EDEBT EDEBB EDET EDEB EDE/P EDEBT/P EDEBB/P EDET/P EDEB/P
    SSSC SSSC/F SSSC/P SSSC/F/P
    SSSC/K4 SSSC/K5 SSSC/F/K4 SSSC/F/K5 SSSC/P/K4 SSSC/P/K5 SSSC/F/P/K4 SSSC/F/P/K5
  )

  defp scope, do: PairingsEngine.AccountsFixtures.user_scope_fixture()

  # The table spelling of every code the picker offers for `type`.
  defp offered_c07(type) do
    c07 =
      if type in ~w(team-swiss team-roundrobin),
        do: TeamStandings.c07_codes(),
        else: AinalramiBridge.codes()

    for %{code: code} <- Tiebreaks.selectable(type), code != "EXT", do: Map.get(c07, code, code)
  end

  # A table code as the app stores it: through the alias the app has always
  # used for it, if there is one.
  defp stored_valid?(table_code, type) do
    c07 =
      if type in ~w(team-swiss team-roundrobin),
        do: TeamStandings.c07_codes(),
        else: AinalramiBridge.codes()

    reverse = for {code, spelled} <- c07, into: %{}, do: {String.upcase(spelled), code}
    up = String.upcase(table_code)
    Tiebreaks.valid?(Map.get(reverse, up, up), type)
  end

  # Every state of the builder: each family with every modifier it accepts.
  defp builder_states(type) do
    for {_group, list} <- Builder.families(type),
        {family, _label} <- list,
        spec = Builder.spec(type, family),
        ref <- Map.get(spec, :refs, [""]),
        cut <- Map.get(spec, :cuts, [""]),
        variant <- Map.get(spec, :variants, [""]),
        limit <- Map.get(spec, :limits, [""]),
        forfeits <- if(spec[:forfeits?], do: ["false", "true"], else: ["false"]),
        fore <- if(spec[:fore?], do: ["false", "true"], else: ["false"]),
        reversed <- if(spec[:reversed?], do: ["false", "true"], else: ["false"]),
        factor <- if(spec[:factor?], do: ["", "4", "5"], else: [""]) do
      %{
        "family" => family,
        "ref" => ref,
        "cut" => cut,
        "variant" => variant,
        "limit" => limit,
        "forfeits" => forfeits,
        "fore" => fore,
        "reversed" => reversed,
        "factor" => factor
      }
    end
  end

  describe "the table" do
    test "is 158 codes, as Ainalrami counts them" do
      assert length(@individual ++ @team) == 158
    end

    test "every individual code is a valid tie-break of an individual tournament" do
      assert Enum.reject(@individual, &stored_valid?(&1, "swiss")) == []
    end

    test "every team code is a valid tie-break of a team tournament, round robin or Swiss" do
      for type <- ~w(team-swiss team-roundrobin) do
        assert Enum.reject(@team, &stored_valid?(&1, type)) == [], type
      end
    end

    test "the builder can compose every code of the table" do
      for {type, table} <- [{"swiss", @individual}, {"team-swiss", @team}] do
        reachable =
          for state <- builder_states(type),
              {:ok, code} <- [Builder.compose(type, state)],
              into: MapSet.new(),
              do: String.upcase(Builder.c07(type, code))

        assert Enum.reject(table, &MapSet.member?(reachable, String.upcase(&1))) == [], type
      end
    end

    test "every combination the builder offers is a valid tie-break for its tournament" do
      for type <- ~w(swiss roundrobin team-swiss team-roundrobin),
          state <- builder_states(type) do
        assert {:ok, code} = Builder.compose(type, state), "#{type}: #{inspect(state)}"
        assert Tiebreaks.valid?(code, type)
        assert Tiebreaks.get(code), code
      end
    end

    test "a normalising factor is any whole number from 1, and nothing else" do
      assert {:ok, "SSSC/K12"} =
               Builder.compose("team-swiss", %{"family" => "SSSC", "factor" => "12"})

      assert {:error, :factor} =
               Builder.compose("team-swiss", %{"family" => "SSSC", "factor" => "0"})

      assert Tiebreaks.valid?("SSSC/F/P/K99", "team-roundrobin")
      refute Tiebreaks.valid?("SSSC/K0", "team-roundrobin")
      refute Tiebreaks.valid?("SSSC/K4", "swiss")
      refute Tiebreaks.valid?("BH/K4", "team-swiss")
    end

    test "composed codes land on the stored aliases" do
      assert {:ok, "BHC1"} = Builder.compose("swiss", %{"family" => "BH", "cut" => "C1"})
      assert {:ok, "MBH"} = Builder.compose("swiss", %{"family" => "BH", "cut" => "M1"})
      assert {:ok, "AROC1"} = Builder.compose("swiss", %{"family" => "ARO", "cut" => "C1"})
      assert {:ok, "BH"} = Builder.compose("team-swiss", %{"family" => "BH", "ref" => "MP"})
      assert {:ok, "BHC2"} = Builder.compose("team-swiss", %{"family" => "BH", "cut" => "C2"})
      assert {:ok, "SB"} = Builder.compose("team-swiss", %{"family" => "SB"})
      assert {:ok, "MP"} = Builder.compose("team-swiss", %{"family" => "MP"})
    end

    test "every offered code is one Ainalrami parses back to itself" do
      for type <- ~w(swiss team-roundrobin), c07 <- offered_c07(type) do
        assert {:ok, code} = Code.parse(c07), c07
        assert Code.format(code) == String.upcase(c07)
      end
    end

    test "the individual /P codes go through the bridge under their own spelling" do
      for code <- PairingsEngine.Tiebreaks.TableCodes.individual_codes() do
        assert AinalramiBridge.c07_code(code) == code
        assert %{scope: :individual} = Tiebreaks.get(code)
      end
    end

    test "a team code is no individual code: individual standings drop it" do
      t = %Tournament{tiebreaks: ~w(BH SSSC/K4 EMMSB/P)}

      assert Standings.dropped_tiebreaks_with_reasons(t, []) ==
               [{"SSSC/K4", :not_calculable}, {"EMMSB/P", :not_calculable}]
    end
  end

  # An individual Swiss with one forfeit in round 2.
  @results ~w(1-0 0-1 1/2-1/2 1-0 0-1)

  defp swiss_with_forfeit(tiebreaks) do
    t =
      Repo.insert!(%Tournament{
        name: "Forfeit",
        type: "swiss",
        rounds_count: 5,
        tiebreaks: tiebreaks,
        round_dates: for(r <- 1..5, do: "2026-09-0#{r}")
      })

    for i <- 1..10 do
      {:ok, _} =
        Tournaments.create_player(t.id, %{
          tournament_id: t.id,
          name: "Player #{i}",
          fide_rating: 2400 - 37 * i
        })
    end

    for _ <- 1..5 do
      {:ok, round} = Pairing.pair_next_round(Repo.reload!(t), [])
      round = Tournaments.get_round(t.id, round.number)

      for {p, i} <- Enum.with_index(round.pairings), p.black_player_id do
        result =
          case {round.number, i} do
            {2, 0} -> "1-0FF"
            {3, 1} -> "0-1FF"
            {4, 2} -> "1-0FF"
            _ -> Enum.at(@results, rem(i + round.number, 5))
          end

        {:ok, _} = Tournaments.update_pairing_result(p, result)
      end
    end

    Repo.reload!(t)
  end

  defp checker_exit(text) do
    path = Path.join(System.tmp_dir!(), "op_table_#{System.unique_integer([:positive])}.trf")
    File.write!(path, text)

    try do
      {_, _} =
        with_io(:stderr, fn ->
          capture_io(fn -> send(self(), {:code, Ainalrami.CLI.run([path, "-c"])}) end)
        end)

      receive do: ({:code, code} -> code)
    after
      File.rm(path)
    end
  end

  describe "/P on a tournament with a forfeit" do
    @p_codes ~w(BH/P BH/C1/P BH/C2/P BH/M1/P BH/M2/P FB/P FB/C1/P FB/C2/P FB/M1/P FB/M2/P
                SB/P SB/C1/P SB/C2/P)

    test "each value is Ainalrami's, read from the TRF the app writes" do
      t = swiss_with_forfeit(@p_codes)
      assert Standings.dropped_tiebreaks(t) == []
      {:ok, text} = TrfExport.export(t)
      event = text |> Ainalrami.Trf.parse() |> Event.from_trf()
      entries = Standings.standings(t)

      for code <- @p_codes do
        {:ok, values} = Ainalrami.Tiebreaks.compute(event, [code])
        theirs = values[code]
        assert is_map(theirs), "#{code}: the checker dropped it"

        for entry <- entries do
          assert_in_delta entry.tiebreaks[code],
                          (theirs[entry.player.pairing_number] || 0) * 1.0,
                          1.0e-6,
                          "#{code}, player #{entry.player.pairing_number}"
        end
      end
    end

    test "counting the forfeit changes a Buchholz value" do
      t = swiss_with_forfeit(~w(BH BH/P))
      entries = Standings.standings(t)

      assert Enum.any?(entries, &(&1.tiebreaks["BH"] != &1.tiebreaks["BH/P"]))
    end

    test "the TRF 202 line carries the codes and the import reads them back" do
      list = ~w(BH/P FB/C1/P SB/C2/P)
      t = swiss_with_forfeit(list)
      {:ok, text} = TrfExport.export(t)

      assert text =~ ~r/^202 .*BH\/P/m
      assert checker_exit(text) == 0

      {:ok, imported, _notes} = TrfImport.import_text(text, scope())
      assert imported.tiebreaks == list
    end
  end

  defp team_example(user_scope) do
    {t, _} =
      team_round_robin(
        [
          {"Antwerp Knights", [2210, 2105]},
          {"Brugse SK", [2150, 2000]},
          {"Charleroi", [1900, 1850]},
          {"Deurne", [1800, 1750]}
        ],
        user_id: user_scope.user.id,
        start_date: "2026-09-01",
        end_date: "2026-09-03",
        round_dates: ["2026-09-01", "2026-09-02", "2026-09-03"]
      )

    t = pair_all!(t)
    enter!(t, 1, "Antwerp Knights", "Deurne", ["1-0", "1/2-1/2"])
    enter!(t, 1, "Brugse SK", "Charleroi", ["0-1", "1-0"])
    enter!(t, 2, "Deurne", "Charleroi", ["1-0", "0-1"])
    {:ok, t} = t |> Repo.reload!() |> Tournaments.leave_fide_mode()
    t
  end

  describe "team events" do
    test "every offered team code is calculated, Buchholz-based ones aside in a round robin" do
      t = team_example(scope())
      codes = t.type |> Tiebreaks.selectable() |> Enum.map(& &1.code)
      {:ok, t} = Tournaments.update_tournament(t, %{tiebreaks: codes})

      dropped = TeamStandings.dropped_tiebreaks_with_reasons(t)

      assert Enum.all?(dropped, fn {code, reason} ->
               reason == :round_robin and
                 (code in ~w(BH BHC1 BHC2 MBH) or
                    String.starts_with?(code, ["BH:", "FB:", "AOB:"]))
             end)

      dropped_codes = Enum.map(dropped, &elem(&1, 0))
      standings = TeamStandings.standings(t)
      assert length(standings) == 4

      for code <- codes -- ["DE" | dropped_codes], entry <- standings do
        assert is_number(entry.tiebreaks[code]), "#{code} produced no number"
      end
    end

    test "the TRF 212 line carries the new team codes and the import reads them back" do
      user_scope = scope()
      t = team_example(user_scope)
      list = ~w(MP GP PS:MP/C1 KS:GP/L-2 EMMSB/C1/P EGGSB/P EDEBT/P SSSC/F/P/K4 MPVGP WIN:MP)
      {:ok, t} = Tournaments.update_tournament(t, %{tiebreaks: list})
      {:ok, text} = TrfExport.export(t)

      assert text =~ "SSSC/F/P/K4"

      {:ok, imported, _notes} = TrfImport.import_text(text, user_scope)
      assert imported.tiebreaks == list
    end
  end
end
