defmodule PairingsEngineWeb.ManubriumApi.HallController do
  @moduledoc """
  The hall apps from the Manubrium app: whether the print stations and
  announcers (Polis, Nunki) are online, and three commands for them - print
  again, start or cancel the countdown, say something.

  The core knows no hall app. The plugins that are compiled in answer
  through `PairingsEngine.Plugins.hall_status/2` and `hall_command/3`, and
  the frames they send are the `hall-link-v1` contract's (`print`,
  `standings`, `countdown`, `announce`). The request and answer shapes are
  `manubrium-v1`'s: `hall-response` and the three `hall-*-request`.

  A command goes to the devices that are online; `sent_to` says how many,
  and 0 is an answer, not an error: a hall PC that is off is the arbiter's
  business, not the API's. The owner and editors only (`Reply.tournament/3`'s
  `:desk`), as everywhere that touches the tournament's setup.
  """
  use PairingsEngineWeb, :controller

  alias PairingsEngine.{Plugins, Tournaments}
  alias PairingsEngineWeb.ManubriumApi.Reply

  @what ~w(pairings placecards both standings playerlist slips)
  @canned ~w(silence phones seats results arbiter)
  @minutes [1, 2, 5, 10, 15, 20, 30]
  @text_max 300

  @doc "GET /tournaments/:id/hall - what is switched on, who is joined and online."
  def show(conn, %{"id" => id}) do
    with {:ok, t, _role} <- Reply.tournament(conn, id, :desk) do
      statuses = Plugins.hall_status(conn.assigns.current_scope, t)

      json(conn, %{
        apps: Enum.map(statuses, & &1.app),
        devices: Enum.flat_map(statuses, &devices/1),
        round: latest_round(t),
        countdown: Enum.find_value(statuses, & &1.countdown) |> countdown_json()
      })
    else
      {:halt, conn} -> conn
    end
  end

  @doc "POST /tournaments/:id/hall/print - `{what}`: print the latest round's sheets again."
  def print(conn, %{"id" => id, "what" => what}) when what in @what do
    command(conn, id, {:print, what})
  end

  def print(conn, _params),
    do: bad_request(conn, gettext("Not something a print station prints."))

  @doc "POST /tournaments/:id/hall/countdown - `{minutes}` or `{cancel: true}`."
  def countdown(conn, %{"id" => id, "minutes" => minutes}) when minutes in @minutes do
    command(conn, id, {:countdown, minutes})
  end

  def countdown(conn, %{"id" => id, "cancel" => true}), do: command(conn, id, :cancel_countdown)

  def countdown(conn, _params),
    do: bad_request(conn, gettext("A countdown is 1, 2, 5, 10, 15, 20 or 30 minutes."))

  @doc "POST /tournaments/:id/hall/announce - `{canned}` or `{text}`."
  def announce(conn, %{"id" => id} = params) do
    canned = if params["canned"] in @canned, do: params["canned"]

    text =
      case params["text"] do
        text when is_binary(text) -> text |> String.trim() |> String.slice(0, @text_max)
        _none -> nil
      end

    text = if text == "", do: nil, else: text

    if canned || text,
      do: command(conn, id, {:announce, canned, text}),
      else: bad_request(conn, gettext("Say what to announce."))
  end

  ## ---------- commands ----------

  defp command(conn, id, command) do
    with {:ok, t, _role} <- Reply.tournament(conn, id, :desk) do
      case Plugins.hall_command(conn.assigns.current_scope, t, command) do
        {:ok, sent_to} ->
          json(conn, answer(conn, t, command, sent_to))

        {:error, :no_hall} ->
          Reply.error(
            conn,
            409,
            "hall_off",
            gettext("No hall app is switched on for this account.")
          )

        {:error, :no_round} ->
          Reply.error(conn, 409, "hall_no_round", gettext("Publish a round first."))

        {:error, :no_standings} ->
          Reply.error(
            conn,
            409,
            "hall_failed",
            gettext("There are no standings to print yet, or this event may not print them.")
          )

        {:error, _other} ->
          Reply.error(conn, 409, "hall_failed", gettext("The hall apps could not take that."))
      end
    else
      {:halt, conn} -> conn
    end
  end

  # The countdown commands answer with the one running now, so the phone
  # need not ask again.
  defp answer(conn, t, {:countdown, _minutes}, sent_to),
    do: %{sent_to: sent_to, round: latest_round(t), countdown: running(conn, t)}

  defp answer(_conn, t, :cancel_countdown, sent_to),
    do: %{sent_to: sent_to, round: latest_round(t), countdown: nil}

  defp answer(_conn, t, _command, sent_to), do: %{sent_to: sent_to, round: latest_round(t)}

  defp running(conn, t) do
    conn.assigns.current_scope
    |> Plugins.hall_status(t)
    |> Enum.find_value(& &1.countdown)
    |> countdown_json()
  end

  ## ---------- shapes ----------

  defp devices(%{app: app, devices: devices}) do
    for d <- Enum.sort_by(devices, &{String.downcase(&1.name), &1.id}) do
      %{
        app: app,
        id: d.id,
        name: d.name,
        room: d.room || "",
        online: d.online,
        last_seen_at: d.last_seen_at && DateTime.to_iso8601(d.last_seen_at)
      }
    end
  end

  defp countdown_json(nil), do: nil

  defp countdown_json(%{round: round, seconds_left: seconds}),
    do: %{round: round, seconds_left: seconds}

  defp latest_round(t) do
    case Tournaments.latest_published_round_number(t) do
      0 -> nil
      n -> n
    end
  end

  defp bad_request(conn, message), do: Reply.error(conn, 400, "bad_request", message)
end
