defmodule PairingsEngine.Tiebreaks.Custom do
  @moduledoc """
  The tournament's own tie-break: a weighted sum of figures the app already
  counts per player, stored on the tournament (`custom_tiebreak`) and put on
  the tie-break list as the code `CUSTOM`.

  It exists because an organiser wanted "forfeits lost, the more the worse",
  and C.07 has no such thing. C.07 also does not forbid it: the choice of
  tie-breaks belongs to the tournament regulations, announced in advance.
  So it changes neither a pairing nor a game's value, and does not take a
  tournament out of FIDE mode - it is only ever marked "custom" wherever it
  shows, so nobody mistakes it for one of FIDE's.

  ## The shape

      %{
        "preset" => "forfeits_lost" | "forfeits_won" | "custom",
        "direction" => "higher" | "lower",
        "terms" => [%{"figure" => "forfeit_losses", "sign" => "-", "weight" => 1.0}]
      }

  A formula is data, never code: a figure is one of `figures/0`, a sign is
  `+` or `-`, a weight is a number from 0 to 1000. Nothing typed is ever
  evaluated - `value/2` multiplies and adds, and that is the whole language.

  `direction` is how the total ranks: `"higher"` puts the higher total
  first, `"lower"` the lower. With signs per term and a direction for the
  whole, "we like forfeits" and "we don't" are both one click away.
  """

  use Gettext, backend: PairingsEngineWeb.Gettext

  @figures [
    {"wins", gettext_noop("Wins over the board")},
    {"draws", gettext_noop("Draws over the board")},
    {"losses", gettext_noop("Losses over the board")},
    {"games", gettext_noop("Games played over the board")},
    {"forfeit_wins", gettext_noop("Forfeit wins")},
    {"forfeit_losses", gettext_noop("Forfeit losses")},
    {"full_byes", gettext_noop("Full-point byes (not the pairing-allocated bye)")},
    {"half_byes", gettext_noop("Half-point byes")},
    {"zero_byes", gettext_noop("Zero-point byes")},
    {"pab", gettext_noop("Pairing-allocated byes received")},
    {"black_games", gettext_noop("Games played with Black")},
    {"black_wins", gettext_noop("Games won with Black")},
    {"unplayed", gettext_noop("Unplayed rounds")},
    {"points", gettext_noop("Points")},
    {"bh", gettext_noop("Buchholz")},
    {"sb", gettext_noop("Sonneborn-Berger")}
  ]

  @figure_ids Enum.map(@figures, &elem(&1, 0))

  # The C.07 code a figure is read from, for the two that are tie-breaks of
  # their own. Computed by Ainalrami like any other column.
  @computed %{"bh" => "BH", "sb" => "SB"}

  @max_terms 8
  @max_weight 1000

  @presets [
    {"forfeits_lost",
     %{
       "preset" => "forfeits_lost",
       "direction" => "higher",
       "terms" => [%{"figure" => "forfeit_losses", "sign" => "-", "weight" => 1.0}]
     }},
    {"forfeits_won",
     %{
       "preset" => "forfeits_won",
       "direction" => "higher",
       "terms" => [%{"figure" => "forfeit_wins", "sign" => "+", "weight" => 1.0}]
     }},
    {"custom", %{"preset" => "custom", "direction" => "higher", "terms" => []}}
  ]

  @doc "The code the formula sits under in a tournament's tie-break list."
  def code, do: "CUSTOM"

  @doc "`[{id, English label}]`, in the order the builder offers them."
  def figures, do: @figures

  @doc "The English label of a figure id."
  def figure_label(id), do: Enum.find_value(@figures, id, fn {f, l} -> if f == id, do: l end)

  @doc "A figure's label in the current locale."
  def figure_text(id), do: Gettext.gettext(PairingsEngineWeb.Gettext, figure_label(id))

  @preset_texts %{
    "forfeits_lost" =>
      {gettext_noop("Forfeits lost (fewer is better)"),
       gettext_noop(
         "The sensible one, and the default. Every forfeit loss counts -1 and the higher total ranks first, so of two players level on everything above it, the one who failed to turn up less often goes first. A forfeit loss is a game lost without being played; byes and games lost at the board do not count."
       )},
    "forfeits_won" =>
      {gettext_noop("Forfeits won count for you"),
       gettext_noop(
         "The other way round. Every forfeit win counts +1 and the higher total ranks first, so of two players level on everything above it, the one whose opponents stayed away more often goes first. Unusual, but a forfeit win is still a point scored, and some regulations want it rewarded."
       )},
    "custom" =>
      {gettext_noop("Your own formula"),
       gettext_noop(
         "Start from nothing: add the figures you want, each with a sign and a weight, and say whether the higher or the lower total ranks first. Write the same formula into the tournament regulations, word for word."
       )}
  }

  @doc "`{name, explanation}` of a preset, in the current locale."
  def preset_text(id) do
    {name, explanation} = Map.get(@preset_texts, id, @preset_texts["custom"])

    {Gettext.gettext(PairingsEngineWeb.Gettext, name),
     Gettext.gettext(PairingsEngineWeb.Gettext, explanation)}
  end

  @doc """
  The formula in the current locale, marked as the tournament's own: what a
  column heading's label, a print's footnote and the published standings say.
  """
  def label(formula) do
    gettext("Custom tie-break, not FIDE: %{formula}",
      formula: describe_local(formula)
    )
  end

  @doc "`describe/4` in the current locale."
  def describe_local(formula) do
    describe(formula, &figure_text/1, gettext("higher is better"), gettext("lower is better"))
  end

  @doc "The preset ids, in the order the builder offers them."
  def preset_ids, do: Enum.map(@presets, &elem(&1, 0))

  @doc "A preset's formula; `forfeits_lost`, the sensible one, for anything unknown."
  def preset(id) do
    Enum.find_value(@presets, fn {k, f} -> if k == id, do: f end) || preset("forfeits_lost")
  end

  @doc "The formula a fresh builder starts from."
  def default, do: preset("forfeits_lost")

  @doc "The most terms a formula takes."
  def max_terms, do: @max_terms

  @doc """
  A well-formed formula from whatever arrives - a form, a JSON file, a
  database row - or `nil` for nothing usable. Unknown figures, signs and
  weights outside 0..1000 are dropped term by term rather than refused, so a
  half-edited row never costs the rest.
  """
  def normalize(nil), do: nil

  def normalize(%{} = map) do
    map = Map.new(map, fn {k, v} -> {to_string(k), v} end)

    terms =
      map
      |> Map.get("terms", [])
      |> as_list()
      |> Enum.map(&normalize_term/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.take(@max_terms)

    %{
      "preset" => if(map["preset"] in preset_ids(), do: map["preset"], else: "custom"),
      "direction" =>
        if(map["direction"] in ["higher", "lower"], do: map["direction"], else: "higher"),
      "terms" => terms
    }
  end

  def normalize(_), do: nil

  # A form posts rows as %{"0" => row, "1" => row}; keep their order.
  defp as_list(list) when is_list(list), do: list

  defp as_list(%{} = map) do
    map
    |> Enum.sort_by(fn {k, _} -> int_or_max(k) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp as_list(_), do: []

  defp int_or_max(k) do
    case Integer.parse(to_string(k)) do
      {n, ""} -> n
      _ -> 1_000_000
    end
  end

  defp normalize_term(%{} = term) do
    term = Map.new(term, fn {k, v} -> {to_string(k), v} end)

    with figure when figure in @figure_ids <- term["figure"],
         sign when sign in ["+", "-"] <- term["sign"] || "+",
         {:ok, weight} <- weight(term["weight"]) do
      %{"figure" => figure, "sign" => sign, "weight" => weight}
    else
      _ -> nil
    end
  end

  defp normalize_term(_), do: nil

  @doc "`{:ok, float}` for a weight from 0 to 1000 (comma or point), else `:error`."
  def weight(value) when is_integer(value), do: weight(value * 1.0)

  def weight(value) when is_float(value) do
    if value >= 0 and value <= @max_weight, do: {:ok, Float.round(value, 3)}, else: :error
  end

  def weight(value) when is_binary(value) do
    case value |> String.trim() |> String.replace(",", ".") |> Float.parse() do
      {f, ""} -> weight(f)
      _ -> :error
    end
  end

  def weight(_), do: :error

  @doc "Whether the formula has anything to add up."
  def usable?(%{"terms" => [_ | _]}), do: true
  def usable?(_), do: false

  @doc "The C.07 codes the formula reads a figure from (Buchholz, SB)."
  def computed_codes(formula) do
    for %{"figure" => f} <- terms(formula), code = @computed[f], uniq: true, do: code
  end

  defp terms(%{"terms" => terms}) when is_list(terms), do: terms
  defp terms(_), do: []

  @doc """
  Every figure for one standings entry: `games` is the entry's game list
  (`Standings`' records), `computed` the C.07 values already worked out for
  this player (`%{"BH" => 12.5}`).
  """
  def figures_for(entry, tournament, computed \\ %{}) do
    games = Map.get(entry, :games, [])
    played = Enum.filter(games, & &1.played)
    forfeits = Enum.filter(games, &(not &1.played and &1.opponent_id != nil))
    byes = Enum.filter(games, &(&1.opponent_id == nil and not &1.played))
    {pab, other_byes} = Enum.split_with(byes, &(&1.bye_type == "pairing-allocated"))
    black = Enum.filter(played, &(&1.colour == :b))
    completed = Map.get(entry, :completed_rounds, 0) || 0

    %{
      "wins" => Enum.count(played, &(&1.outcome == :win)),
      "draws" => Enum.count(played, &(&1.outcome == :draw)),
      "losses" => Enum.count(played, &(&1.outcome == :loss)),
      "games" => length(played),
      "forfeit_wins" => Enum.count(forfeits, &(&1.outcome == :win)),
      "forfeit_losses" => Enum.count(forfeits, &(&1.outcome == :loss)),
      "full_byes" => Enum.count(other_byes, &(bye_kind(&1, tournament) == :full)),
      "half_byes" => Enum.count(other_byes, &(bye_kind(&1, tournament) == :half)),
      "zero_byes" => Enum.count(other_byes, &(bye_kind(&1, tournament) == :zero)),
      "pab" => length(pab),
      "black_games" => length(black),
      "black_wins" => Enum.count(black, &(&1.outcome == :win)),
      "unplayed" => max(completed - length(played), 0),
      "points" => Map.get(entry, :points, 0.0) * 1.0,
      "bh" => (computed["BH"] || 0) * 1.0,
      "sb" => (computed["SB"] || 0) * 1.0
    }
  end

  # What a bye paid, against what a win and a draw pay. A draw-sized bye in
  # a tournament where a draw pays what a loss does is a zero bye - nothing
  # earned is nothing earned.
  defp bye_kind(%{points: points}, t) do
    cond do
      points > 0 and points >= t.points_win -> :full
      points > 0 and points == t.points_draw -> :half
      true -> :zero
    end
  end

  @doc """
  `{total, parts}`: the formula's value and, per term, what it added -
  `%{figure, sign, weight, count, value}` - which the standings show as the
  working. `figures` is `figures_for/3`'s map.
  """
  def evaluate(formula, figures) do
    parts =
      for %{"figure" => f, "sign" => s, "weight" => w} <- terms(formula) do
        count = Map.get(figures, f, 0)
        value = if(s == "-", do: -1, else: 1) * w * count

        %{figure: f, sign: s, weight: w, count: count, value: value}
      end

    total = parts |> Enum.map(& &1.value) |> Enum.sum() |> Kernel.*(1.0) |> Float.round(3)
    {total, parts}
  end

  @doc """
  The key the standings sort on, ascending: the total negated when higher
  is better, the total itself when lower is.
  """
  def sort_key(value, %{"direction" => "lower"}), do: value || 0.0
  def sort_key(value, _formula), do: -(value || 0.0)

  @doc "Whether this formula ranks the lower total first."
  def lower_better?(%{"direction" => "lower"}), do: true
  def lower_better?(_), do: false

  @doc """
  The formula in words, English labels: `−1 × Forfeit losses; higher is
  better`. `label` maps a figure id to the text shown for it.
  """
  def describe(
        formula,
        label \\ &figure_label/1,
        higher \\ "higher is better",
        lower \\ "lower is better"
      )

  def describe(formula, label, higher, lower) do
    body =
      case terms(formula) do
        [] ->
          "0"

        [first | rest] ->
          head = term_text(first, label, true)
          Enum.reduce(rest, head, fn t, acc -> acc <> " " <> term_text(t, label, false) end)
      end

    body <> "; " <> if(lower_better?(formula), do: lower, else: higher)
  end

  defp term_text(%{"sign" => s, "weight" => w, "figure" => f}, label, first?) do
    sign =
      cond do
        first? and s == "+" -> ""
        first? -> "−"
        s == "+" -> "+ "
        true -> "− "
      end

    sign <> format_number(w) <> " × " <> label.(f)
  end

  @doc "A number the way the builder shows it: no trailing `.0`."
  def format_number(n) when is_integer(n), do: Integer.to_string(n)

  def format_number(n) when is_float(n) do
    if n == Float.round(n, 0),
      do: n |> trunc() |> Integer.to_string(),
      else: n |> Float.round(3) |> :erlang.float_to_binary([:compact, decimals: 3])
  end

  def format_number(n), do: to_string(n)

  @doc """
  One player's working: `−1 × Forfeit losses (2) = −2`, terms joined by
  ` + `. `label` as for `describe/4`.
  """
  def working_text(parts, total, label \\ &figure_label/1) do
    body =
      Enum.map_join(parts, " + ", fn p ->
        sign = if p.sign == "-", do: "−", else: ""
        "#{sign}#{format_number(p.weight)} × #{label.(p.figure)} (#{format_number(p.count)})"
      end)

    if body == "", do: "0", else: body <> " = " <> format_number(total)
  end
end
