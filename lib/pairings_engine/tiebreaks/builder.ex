defmodule PairingsEngine.Tiebreaks.Builder do
  @moduledoc """
  The tie-break picker as a builder: a short list of base families, and for
  the chosen family only the modifiers it accepts (cut or median, forfeits
  counted, fore, score basis, Koya limit, SSSC's normalising factor).

  `compose/2` turns the choices into the code a tournament stores. Where the
  app has always spelt a C.07 code its own way (`BH/C1` is `BHC1`, `BH/M1` is
  `MBH`, `ARO/C1` is `AROC1`, team `BH:MP` is `BH`) the stored code is that
  alias, so tournaments saved before the builder keep reading and writing the
  same codes; every other combination is stored under C.07's spelling, which
  is also what a TRF `202`/`212` line carries.
  """

  alias PairingsEngine.Standings.AinalramiBridge
  alias PairingsEngine.{TeamStandings, Tiebreaks}

  @cuts5 ["", "C1", "C2", "M1", "M2"]
  @cuts3 ["", "C1", "C2"]
  @limits ["", "L1", "L2", "L-1", "L-2"]
  @refs ["MP", "GP"]

  # {id, label, spec}. A spec lists the modifiers the family accepts.
  @individual [
    {:results,
     [
       {"DE", "Direct encounter", %{forfeits?: true}},
       {"WIN", "Number of wins", %{}},
       {"WON", "Games won over the board", %{}},
       {"BPG", "Games played with Black", %{}},
       {"BWG", "Games won with Black", %{}},
       {"REP", "Rounds effectively played", %{}},
       {"STD", "Standard points", %{}},
       {"TPN", "Tournament pairing number", %{reversed?: true}},
       {"EXT", "External value", %{}}
     ]},
    {:buchholz,
     [
       {"BH", "Buchholz", %{cuts: @cuts5, forfeits?: true}},
       {"FB", "Fore Buchholz", %{cuts: @cuts5, forfeits?: true}},
       {"AOB", "Average of opponents' Buchholz", %{fore?: true}}
     ]},
    {:sonneborn,
     [
       {"SB", "Sonneborn-Berger", %{cuts: @cuts3, forfeits?: true}},
       {"KS", "Koya system", %{limits: @limits}}
     ]},
    {:progressive, [{"PS", "Progressive score", %{cuts: @cuts3}}]},
    {:rating,
     [
       {"ARO", "Average rating of opponents", %{cuts: @cuts5}},
       {"TPR", "Tournament performance rating", %{}},
       {"PTP", "Perfect tournament performance", %{}},
       {"APRO", "Average performance rating of opponents", %{}},
       {"APPO", "Average perfect performance of opponents", %{}},
       {"RTNG", "Tournament rating", %{reversed?: true}}
     ]},
    # The tournament's own formula. Its modifiers are the formula itself,
    # held by the page and stored beside the list (`Tiebreaks.Custom`).
    {:custom, [{"CUSTOM", "Custom formula (not FIDE)", %{custom?: true}}]}
  ]

  @team [
    {:team,
     [
       {"MP", "Match points", %{}},
       {"GP", "Game points", %{}},
       {"MPVGP", "Match points or game points", %{}},
       {"DE", "Direct encounter", %{}},
       {"BB", "Board points weighted (Berlin)", %{}},
       {"TBR", "Top Board Results", %{}},
       {"BBE", "Bottom Board Elimination", %{}},
       {"SSSC", "Scores and Schedule Strength Combination",
        %{fore?: true, forfeits?: true, factor?: true}}
     ]},
    {:results,
     [
       {"WIN", "Matches won", %{refs: ["MP"]}},
       {"WON", "Matches won over the board", %{refs: ["MP"]}},
       {"EDE", "Extended Direct Encounter",
        %{variants: ["", "BT", "BB", "T", "B"], forfeits?: true}}
     ]},
    {:buchholz,
     [
       {"BH", "Buchholz", %{refs: @refs, cuts: @cuts5, forfeits?: true}},
       {"FB", "Fore Buchholz", %{refs: @refs, cuts: @cuts5, forfeits?: true}},
       {"AOB", "Average of opponents' Buchholz", %{refs: @refs, fore?: true}}
     ]},
    {:sonneborn,
     [
       {"SB", "Sonneborn-Berger", %{}},
       {"KS", "Koya system", %{refs: @refs, limits: @limits}},
       {"EMMSB", "Extended Sonneborn-Berger, MP x MP", %{cuts: @cuts3, forfeits?: true}},
       {"EMGSB", "Extended Sonneborn-Berger, MP x GP", %{cuts: @cuts3, forfeits?: true}},
       {"EGMSB", "Extended Sonneborn-Berger, GP x MP", %{cuts: @cuts3, forfeits?: true}},
       {"EGGSB", "Extended Sonneborn-Berger, GP x GP", %{cuts: @cuts3, forfeits?: true}}
     ]},
    {:progressive, [{"PS", "Progressive score", %{refs: @refs, cuts: @cuts3}}]}
  ]

  @default %{
    "family" => "",
    "ref" => "",
    "cut" => "",
    "variant" => "",
    "limit" => "",
    "reversed" => "false",
    "fore" => "false",
    "forfeits" => "false",
    "factor" => ""
  }

  def team_type?(type), do: type in ["team-swiss", "team-roundrobin"]

  @doc "`[{group, [{id, label}]}]`: the base families a tournament of `type` is offered."
  def families(type) do
    for {group, list} <- groups(type), do: {group, Enum.map(list, fn {id, l, _} -> {id, l} end)}
  end

  defp groups(type), do: if(team_type?(type), do: @team, else: @individual)

  @doc "The modifiers `family` accepts in a tournament of `type`; `nil` for no such family."
  def spec(type, family) do
    Enum.find_value(groups(type), fn {_g, list} ->
      Enum.find_value(list, fn {id, _l, spec} -> if id == family, do: spec end)
    end)
  end

  @doc "Fresh builder state starting at the first family."
  def initial(type) do
    [{_g, [{id, _} | _]} | _] = families(type)
    normalize(type, %{"family" => id})
  end

  @doc """
  Builder state from form params: unknown or inapplicable modifiers are reset,
  and a reference score defaults to match points.
  """
  def normalize(type, params) do
    params = Map.merge(@default, Map.take(params, Map.keys(@default)))
    spec = spec(type, params["family"])

    if spec == nil do
      initial(type)
    else
      refs = Map.get(spec, :refs, [])

      %{
        "family" => params["family"],
        "ref" => if(refs == [], do: "", else: pick(params["ref"], refs, hd(refs))),
        "cut" => pick(params["cut"], Map.get(spec, :cuts, [""]), ""),
        "variant" => pick(params["variant"], Map.get(spec, :variants, [""]), ""),
        "limit" => pick(params["limit"], Map.get(spec, :limits, [""]), ""),
        "reversed" => flag(spec[:reversed?], params["reversed"]),
        "fore" => flag(spec[:fore?], params["fore"]),
        "forfeits" => flag(spec[:forfeits?], params["forfeits"]),
        "factor" => if(spec[:factor?], do: digits(params["factor"]), else: "")
      }
    end
  end

  defp pick(value, allowed, default), do: if(value in allowed, do: value, else: default)
  defp flag(true, value), do: if(value in ["true", "on", true], do: "true", else: "false")
  defp flag(_, _), do: "false"
  defp digits(value), do: value |> to_string() |> String.replace(~r/\D/, "") |> String.slice(0, 6)

  @doc """
  `{:ok, stored_code}` for the builder state, `{:error, :factor}` while a
  normalising factor is typed but not a whole number from 1, or `:error`.
  """
  def compose(type, state) do
    state = normalize(type, state)
    family = state["family"]

    cond do
      state["factor"] != "" and String.to_integer(state["factor"]) < 1 ->
        {:error, :factor}

      family in ~w(MP GP BB) and team_type?(type) ->
        {:ok, family}

      true ->
        head =
          cond do
            family == "EDE" -> "EDE" <> state["variant"]
            state["ref"] != "" -> family <> ":" <> state["ref"]
            true -> family
          end

        c07 =
          head <>
            suffix(state["cut"]) <>
            suffix(state["limit"]) <>
            if(state["reversed"] == "true", do: "/R", else: "") <>
            if(state["fore"] == "true", do: "/F", else: "") <>
            if(state["forfeits"] == "true", do: "/P", else: "") <>
            if(state["factor"] != "", do: "/K" <> state["factor"], else: "")

        code = Map.get(aliases(type), c07, c07)
        if Tiebreaks.valid?(code, type), do: {:ok, code}, else: :error
    end
  end

  defp suffix(""), do: ""
  defp suffix(mod), do: "/" <> mod

  # C.07 spelling => the code this app has always stored for it.
  defp aliases(type) do
    map = if team_type?(type), do: TeamStandings.c07_codes(), else: AinalramiBridge.codes()
    for {code, c07} <- map, code != c07, into: %{}, do: {c07, code}
  end

  @doc "The C.07 spelling of a stored code, as the TRF `202` line writes it."
  def c07(type, code) do
    map = if team_type?(type), do: TeamStandings.c07_codes(), else: AinalramiBridge.codes()
    Map.get(map, code, code)
  end
end
