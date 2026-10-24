defmodule PairingsEngine.Tiebreaks.TableCodes do
  @moduledoc """
  The codes of FIDE's "Mandatory Tie-Breaks - TRF26" table that the hand
  written part of `PairingsEngine.Tiebreaks` does not list: `/P` (forfeits
  count as games against the scheduled opponent) on the Buchholz and
  Sonneborn-Berger family, the team forms of the same family, the four
  extended Sonneborn-Bergers, the extended direct encounters, SSSC's `/F`,
  `/P` and `/K<n>`, and the rest of the team table.

  The table lists 158 codes (Ainalrami counts `Lx` and `Kx` with two values
  each). Their stored code is C.07's own spelling, which is also what a TRF
  `202`/`212` record carries, so there is no translation table to keep in
  step: the generated entries are the translation.

  Values come from Ainalrami (`PairingsEngine.Standings.AinalramiBridge` for
  individual events, `PairingsEngine.TeamStandings` for team events). This
  module only says what exists, what it is called and where the picker puts
  it.
  """

  @cuts [{"", ""}, {"/C1", "Cut-1"}, {"/C2", "Cut-2"}, {"/M1", "Median-1"}, {"/M2", "Median-2"}]
  @limits [
    {"/L1", "limit +1/2"},
    {"/L2", "limit +1"},
    {"/L-1", "limit -1/2"},
    {"/L-2", "limit -1"}
  ]

  @doc "Individual codes: `/P` on Buchholz, Fore Buchholz and Sonneborn-Berger."
  def individual_codes do
    bh = for base <- ~w(BH FB), {cut, _} <- @cuts, do: base <> cut <> "/P"
    sb = for {cut, _} <- Enum.take(@cuts, 3), do: "SB" <> cut <> "/P"
    bh ++ sb
  end

  @doc "Team codes the table lists and the hand written catalogue does not."
  def team_codes do
    ref = ["MP", "GP"]

    wins = ~w(WIN:MP WON:MP)

    ps = for r <- ref, cut <- ["", "/C1", "/C2"], do: "PS:#{r}#{cut}"

    bh =
      for r <- ref,
          {cut, _} <- @cuts,
          p <- ["", "/P"],
          code = "BH:#{r}#{cut}#{p}",
          # BH:MP, its Cut-1, Cut-2 and Median-1 are the catalogue's BH, BHC1,
          # BHC2 and MBH; BH:GP is its own entry.
          code not in ~w(BH:MP BH:MP/C1 BH:MP/C2 BH:MP/M1 BH:GP),
          do: code

    fb = for r <- ref, {cut, _} <- @cuts, p <- ["", "/P"], do: "FB:#{r}#{cut}#{p}"

    aob = for r <- ref, f <- ["", "/F"], do: "AOB:#{r}#{f}"

    ks = for r <- ref, l <- ["" | Enum.map(@limits, &elem(&1, 0))], do: "KS:#{r}#{l}"

    esb =
      for base <- ~w(EMMSB EMGSB EGMSB EGGSB),
          suffix <- ["", "/C1", "/C2", "/P", "/C1/P", "/C2/P"],
          code = base <> suffix,
          code != "EMGSB",
          # EGMSB and EGGSB exist; their bare forms are not new.
          code not in ~w(EGMSB EGGSB),
          do: code

    ede =
      for base <- ~w(EDE EDEBT EDEBB EDET EDEB),
          p <- ["", "/P"],
          code = base <> p,
          code != "EDE",
          do: code

    sssc =
      for f <- ["", "/F"],
          p <- ["", "/P"],
          k <- ["", "/K4", "/K5"],
          code = "SSSC#{f}#{p}#{k}",
          code != "SSSC",
          do: code

    wins ++ ps ++ bh ++ fb ++ aob ++ ks ++ ["MPVGP"] ++ esb ++ ede ++ sssc
  end

  @doc """
  The catalogue entries for every generated code: `%{code, name, scope,
  available, description, group}`.
  """
  def entries do
    for(code <- individual_codes(), do: entry(code, :individual)) ++
      for code <- team_codes(), do: entry(code, :team)
  end

  defp entry(code, scope) do
    {family, ref, mods} = split(code)

    %{
      code: code,
      name: name(family, ref, mods, scope),
      scope: scope,
      available: true,
      description: description(family, ref, mods, scope),
      group: group(family)
    }
  end

  defp split(code) do
    [head | mods] = String.split(code, "/")

    case String.split(head, ":") do
      [family, ref] -> {family, ref, mods}
      [family] -> {family, nil, mods}
    end
  end

  @family_names %{
    "BH" => "Buchholz",
    "FB" => "Fore Buchholz",
    "SB" => "Sonneborn-Berger",
    "AOB" => "Average of opponents' Buchholz",
    "PS" => "Progressive score",
    "KS" => "Koya system",
    "WIN" => "Number of wins",
    "WON" => "Number of games won over the board",
    "MPVGP" => "Match points or game points",
    "EMMSB" => "Extended Sonneborn-Berger, match points x match points",
    "EMGSB" => "Sonneborn-Berger, match points x game points",
    "EGMSB" => "Extended Sonneborn-Berger, game points x match points",
    "EGGSB" => "Extended Sonneborn-Berger, game points x game points",
    "EDE" => "Extended Direct Encounter",
    "EDEBT" => "Extended Direct Encounter, then Board Count and Top Board Results",
    "EDEBB" => "Extended Direct Encounter, then Board Count and Bottom Board Elimination",
    "EDET" => "Extended Direct Encounter, then Top Board Results",
    "EDEB" => "Extended Direct Encounter, then Bottom Board Elimination",
    "SSSC" => "Scores and Schedule Strength Combination"
  }

  defp name(family, ref, mods, scope) do
    base = Map.fetch!(@family_names, family)
    on = if ref, do: " on #{ref_name(ref)}", else: ""
    plain = if scope == :team and ref != nil, do: on, else: ""
    base <> plain <> mod_names(mods)
  end

  defp ref_name("MP"), do: "match points"
  defp ref_name("GP"), do: "game points"

  defp mod_names([]), do: ""
  defp mod_names(mods), do: ", " <> Enum.map_join(mods, ", ", &mod_name/1)

  defp mod_name("C1"), do: "Cut-1"
  defp mod_name("C2"), do: "Cut-2"
  defp mod_name("M1"), do: "Median-1"
  defp mod_name("M2"), do: "Median-2"
  defp mod_name("F"), do: "over Fore Buchholz"
  defp mod_name("P"), do: "forfeits counted"
  defp mod_name("L1"), do: "limit +1/2"
  defp mod_name("L2"), do: "limit +1"
  defp mod_name("L-1"), do: "limit -1/2"
  defp mod_name("L-2"), do: "limit -1"
  defp mod_name("K" <> n), do: "normalising factor #{n}"

  defp description(family, ref, mods, scope) do
    lead = if scope == :team, do: "Team events: ", else: ""
    forfeits = if "P" in mods, do: " " <> forfeit_sentence(), else: ""
    factor = factor_sentence(mods)
    lead <> base_description(family, ref, scope) <> forfeits <> factor
  end

  defp forfeit_sentence,
    do:
      "Forfeit wins and losses count as games against the scheduled opponent, whose real score is used (C.07, Mandatory Tie-Breaks table)."

  defp factor_sentence(mods) do
    case Enum.find(mods, &String.starts_with?(&1, "K")) do
      "K" <> n -> " The normalising factor is #{n} (C.07 Art. 13.4.2 b)."
      _ -> ""
    end
  end

  defp base_description("BH", ref, _),
    do: "Buchholz#{on(ref)}, with the cut or median in its name."

  defp base_description("FB", ref, _),
    do: "Fore Buchholz#{on(ref)}: the last round counted as a draw for every opponent."

  defp base_description("SB", _, _), do: "Sonneborn-Berger, with the cut in its name."
  defp base_description("AOB", ref, _), do: "Average of the opponents' Buchholz#{on(ref)}."

  defp base_description("PS", ref, _),
    do: "Progressive score#{on(ref)}, with the cut in its name."

  defp base_description("KS", ref, _),
    do: "Koya system#{on(ref)}, with the qualifying limit in its name."

  defp base_description("WIN", _, _), do: "Number of matches won."

  defp base_description("WON", _, _),
    do: "Number of matches won over the board, byes and forfeits left out."

  defp base_description("MPVGP", _, _),
    do: "Match points or game points, whichever the other is not (C.07 Art. 13.1)."

  defp base_description("EMMSB", _, _),
    do:
      "Each opponent's match points times the match points scored against them (C.07 Art. 13.2.1)."

  defp base_description("EMGSB", _, _),
    do:
      "Each opponent's match points times the game points scored against them (C.07 Art. 13.2.2)."

  defp base_description("EGMSB", _, _),
    do:
      "Each opponent's game points times the match points scored against them (C.07 Art. 13.2.3)."

  defp base_description("EGGSB", _, _),
    do:
      "Each opponent's game points times the game points scored against them (C.07 Art. 13.2.4)."

  defp base_description("EDE", _, _),
    do:
      "Direct encounter on match points, then game points, among the tied teams (C.07 Art. 13.3)."

  defp base_description("EDEBT", _, _),
    do: "Extended Direct Encounter, then Board Count, then Top Board Results (C.07 Art. 13.3)."

  defp base_description("EDEBB", _, _),
    do:
      "Extended Direct Encounter, then Board Count, then Bottom Board Elimination (C.07 Art. 13.3)."

  defp base_description("EDET", _, _),
    do: "Extended Direct Encounter, then Top Board Results (C.07 Art. 13.3)."

  defp base_description("EDEB", _, _),
    do: "Extended Direct Encounter, then Bottom Board Elimination (C.07 Art. 13.3)."

  defp base_description("SSSC", _, _),
    do: "The secondary score plus a measure of the opponents' strength (C.07 Art. 13.4)."

  defp on(nil), do: ""
  defp on(ref), do: " on " <> ref_name(ref)

  defp group(family) when family in ~w(BH FB AOB), do: :buchholz
  defp group(family) when family in ~w(SB KS EMMSB EMGSB EGMSB EGGSB), do: :sonneborn
  defp group("PS"), do: :progressive
  defp group(family) when family in ~w(WIN WON EDE EDEBT EDEBB EDET EDEB), do: :results
  defp group(_), do: :team
end
