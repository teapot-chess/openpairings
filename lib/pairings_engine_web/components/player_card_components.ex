defmodule PairingsEngineWeb.PlayerCardComponents do
  @moduledoc """
  The Players Card, shared by every page that can open one: the Players list
  (right-click a row), the Pairings page (the seat menu) and the Standings
  page (the row menu).

  The component only draws. Each LiveView keeps its own `card_player_id`
  assign and answers the same four events (`show_card`, `close_card`,
  `card_prev`, `card_next`); `entries/1`, `parse_id/1` and `adjacent_id/2`
  are the pieces those handlers share.
  """
  use PairingsEngineWeb, :html

  alias PairingsEngine.{PlayerCard, Standings, Tiebreaks}

  @doc "Every player's standings entry, in the order the Players list uses by default."
  def entries(tournament), do: Standings.grid_standings(tournament)

  @doc "Player id -> standings entry, for the card's opponent lookups."
  def by_id(entries), do: Map.new(entries, &{&1.player.id, &1})

  @doc "A whole number out of an event payload, or nil for anything else."
  def parse_id(id) when is_integer(id), do: id

  def parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  def parse_id(_id), do: nil

  @doc "The player `delta` places along `entries` from `current_id`, wrapping round."
  def adjacent_id(entries, current_id, delta) do
    ids = Enum.map(entries, & &1.player.id)

    case Enum.find_index(ids, &(&1 == current_id)) do
      nil -> current_id
      idx -> Enum.at(ids, rem(idx + delta + length(ids), length(ids)))
    end
  end


  attr :entry, :map, default: nil
  attr :by_id, :map, required: true
  attr :tournament, :map, required: true

  def player_card_modal(%{entry: nil} = assigns), do: ~H""

  def player_card_modal(assigns) do
    rows = PlayerCard.rows(assigns.entry, assigns.by_id, assigns.tournament)
    assigns = assign(assigns, rows: rows, totals: PlayerCard.totals(rows, assigns.entry))

    ~H"""
    <div class="modal-overlay" phx-window-keydown="close_card" phx-key="escape">
      <div
        class="modal-card"
        phx-click-away="close_card"
        style="max-width: 900px"
        id="player-card-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="player-card-title"
        tabindex="-1"
        phx-hook="DialogFocus"
        data-dialog
      >
        <h2 id="player-card-title">{gettext("Players Card")}</h2>

        <p class="card-header-line">{PlayerCard.header(@entry)}</p>

        <div :if={@tournament.tiebreaks != []} class="pe-summary" style="margin-bottom: 10px">
          <span :for={code <- @tournament.tiebreaks} class="pe-stat" title={tb_name(code)}>
            <span class="pe-stat-n">{format_num(Map.get(@entry.tiebreaks, code, 0.0))}</span> {code}
          </span>
        </div>

        <div class="card-table-wrap">
          <table class="pe-table">
            <thead>
              <tr>
                <th class="num">N°</th>

                <th class="num">Rnk</th>

                <th>Nat</th>

                <th>Tit</th>

                <th>{gettext("Opponent")}</th>

                <th class="num">{gettext("N-Elo")}</th>

                <th class="num">Pts</th>

                <th class="num">Res</th>

                <th class="num">Cl</th>

                <th class="num">Flt</th>
              </tr>
            </thead>

            <tbody>
              <tr :for={row <- @rows}>
                <td class="num">{row.round}</td>

                <td class="num">{row.opponent_pairing_number || "-"}</td>

                <td>{row.opponent_federation || "-"}</td>

                <td>{blank_dash(row.opponent_title)}</td>

                <td>{row.opponent_name || "-"}</td>

                <td class="num">{row.opponent_elo || "-"}</td>

                <td class="num">{format_num(row.opponent_total)}</td>

                <td class="num">{row.result}</td>

                <td class="num">{row.colour}</td>

                <td class="num">{row.float}</td>
              </tr>

              <tr class="card-total-row">
                <td colspan="6">{gettext("Total")}</td>

                <td class="num">{format_num(@totals.opponent_total)}</td>

                <td class="num">{format_num(@totals.own_total)}</td>

                <td colspan="2"></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="actions">
          <button type="button" class="pe-btn" phx-click="card_prev">{gettext("Previous")}</button>
          <button type="button" class="pe-btn" phx-click="card_next">{gettext("Following")}</button>
          <a
            class="pe-btn"
            href={~p"/t/#{@tournament.id}/print/card/#{@entry.player.id}"}
            target="_blank"
          >
            {gettext("Print")}
          </a>

          <button type="button" class="pe-btn primary" phx-click="close_card">{gettext("Exit")}</button>
        </div>
      </div>
    </div>
    """
  end

  defp blank_dash(nil), do: "-"
  defp blank_dash(""), do: "-"
  defp blank_dash(value), do: value

  defp tb_name(code), do: (Tiebreaks.get(code) || %{name: code}).name

  # Integers render as-is; floats drop a trailing ".0" and trim to the
  # decimals actually present (6.5, 24.25, but zero always shows as "0").
  defp format_num(nil), do: "-"
  defp format_num(n) when is_integer(n), do: Integer.to_string(n)

  defp format_num(n) when is_float(n) do
    if n == Float.round(n, 0) do
      n |> trunc() |> Integer.to_string()
    else
      n
      |> :erlang.float_to_binary(decimals: 2)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
    end
  end
end
