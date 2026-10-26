defmodule PairingsEngine.HandReason do
  @moduledoc """
  The optional reason an arbiter gives for a change made to a pairing by
  hand (a swap, a hand pairing, a moved bye, a round robin's rounds traded).

  Free text, never required and never in the way: a blank reason is no
  reason, and the edit goes through either way. It is kept in the audit row
  of the edit (`details["reason"]`), shown where hand edits are listed, and
  written into the ITDX file's OpenPairings block (`ItdxNotes`).

  Two cleanings, for two readers:

    * `clean/1` is what is stored: control characters and line breaks become
      spaces, runs of spaces collapse, the ends are trimmed and the text is
      cut to `max_length/0` characters. Anything the arbiter typed in another
      script or with accents stays as typed.
    * `ascii/1` is what a TRF file may carry: accents are stripped
      (`e` for the accented e), what has no ASCII shape is dropped.
  """

  @max_length 200

  # The audit actions that can carry a reason: every way the app lets a
  # computed pairing be changed by hand.
  @actions ~w(pairing.players_swapped pairing.player_substituted pairing.seat_vacated
              pairing.bye_awarded pairing.seat_filled pairing.pool_paired pairing.deleted
              pairing.full_point_bye_awarded pairing.full_point_bye_withdrawn
              pairing.rounds_swapped pairing.round_created_by_hand pairing.mpa_finished)

  @doc "The audit action codes whose rows may carry a `reason`."
  def actions, do: @actions

  @doc "The longest reason, in characters."
  def max_length, do: @max_length

  @doc "The reason as it is stored, or nil when there is nothing to store."
  def clean(text) when is_binary(text) do
    text
    |> String.replace(~r/[\x00-\x1F\x7F\x{80}-\x{9F}\x{2028}\x{2029}]+/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_length)
    |> String.trim()
    |> case do
      "" -> nil
      reason -> reason
    end
  end

  def clean(_), do: nil

  @doc """
  `details` with the cleaned `reason` added under `:reason`, or untouched
  when `text` leaves nothing to add.
  """
  def put(details, text) when is_map(details) do
    case clean(text) do
      nil -> details
      reason -> Map.put(details, :reason, reason)
    end
  end

  @doc "The text as plain one-line printable ASCII, for a TRF file."
  def ascii(text) when is_binary(text) do
    (clean(text) || "")
    |> :unicode.characters_to_nfd_binary()
    |> String.to_charlist()
    |> Enum.filter(&(&1 in 32..126))
    |> List.to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def ascii(_), do: ""
end
