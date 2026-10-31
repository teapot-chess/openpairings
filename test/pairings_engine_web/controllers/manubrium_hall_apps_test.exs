defmodule PairingsEngineWeb.ManubriumHallAppsTest do
  @moduledoc """
  The hall apps from Manubrium (`PairingsEngineWeb.ManubriumApi.HallController`):
  who is online, and the three commands. The core knows no hall app, so a
  fake plugin stands in for Polis and Nunki
  (`PairingsEngine.FakePlugin`'s `hall_status/2` and `hall_command/3`); what
  is tested is that the API asks the right question of the plugins and
  words the answer, not what a print station prints.
  """
  use PairingsEngineWeb.ConnCase, async: false

  import PairingsEngine.AccountsFixtures
  import PairingsEngineWeb.ContractHelpers

  alias PairingsEngine.{BoardLinkFixtures, FakePlugin, Manubrium, Repo, Tournaments}
  alias PairingsEngine.Tournaments.Collaborator

  @api "/api/manubrium/v1"

  @status %{
    app: "polis",
    devices: [
      %{
        id: 4,
        name: "Printer desk",
        room: "Hall A",
        online: true,
        last_seen_at: ~U[2026-11-08 13:05:10Z]
      },
      %{id: 2, name: "annex printer", room: nil, online: false, last_seen_at: nil}
    ],
    countdown: nil
  }

  setup do
    owner = user_scope_fixture()
    {:ok, %{secret: secret}} = Manubrium.create_connect_code(owner, "http://test")
    {:ok, _device, token} = Manubrium.redeem(secret, %{"name" => "Test phone"}, "10.1.1.1")

    %{tournament: t, round: round} = BoardLinkFixtures.paired_tournament(owner)

    %{
      owner: owner,
      token: token,
      t: t,
      round: round,
      base: @api <> "/tournaments/#{t.id}/hall"
    }
  end

  defp phone(conn, token) do
    conn
    |> recycle()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  # The round goes public as of a second ago.
  defp publish_round!(round) do
    at = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    round |> Ecto.Changeset.change(published_at: at) |> Repo.update!()
  end

  describe "GET /hall" do
    test "without a plugin there is nothing to show, and the answer fits the contract", %{
      conn: conn,
      token: token,
      base: base
    } do
      answer = conn |> phone(token) |> get(base) |> json_response(200)
      assert answer == %{"apps" => [], "devices" => [], "round" => nil, "countdown" => nil}
      assert_valid!("manubrium-v1", "hall-response.schema.json", answer)
    end

    test "lists the devices of the apps that are on, by name, with their room and last seen", %{
      conn: conn,
      token: token,
      base: base,
      round: round
    } do
      FakePlugin.register(hall_status: @status)
      publish_round!(round)

      answer = conn |> phone(token) |> get(base) |> json_response(200)
      assert_valid!("manubrium-v1", "hall-response.schema.json", answer)

      assert answer["apps"] == ["polis"]
      assert answer["round"] == 1

      assert [
               %{"app" => "polis", "id" => 2, "room" => "", "online" => false},
               %{
                 "id" => 4,
                 "name" => "Printer desk",
                 "room" => "Hall A",
                 "online" => true,
                 "last_seen_at" => "2026-11-08T13:05:10Z"
               }
             ] = answer["devices"]
    end

    test "carries the running countdown", %{conn: conn, token: token, base: base} do
      FakePlugin.register(
        hall_status: %{app: "nunki", devices: [], countdown: %{round: 2, seconds_left: 240}}
      )

      answer = conn |> phone(token) |> get(base) |> json_response(200)
      assert answer["countdown"] == %{"round" => 2, "seconds_left" => 240}
      assert_valid!("manubrium-v1", "hall-response.schema.json", answer)
    end

    test "an arbiter on the tournament is refused, and so is a stranger", %{
      conn: conn,
      owner: owner,
      t: t,
      base: base
    } do
      helper = user_scope_fixture()
      {:ok, c} = Tournaments.add_collaborator(owner, t, helper.user.email, "arbiter")
      {:ok, _} = Tournaments.accept_invitation(helper, c.invite_token)
      _ = Repo.get!(Collaborator, c.id)

      {:ok, %{secret: s}} = Manubrium.create_connect_code(helper, "http://test")
      {:ok, _, helper_token} = Manubrium.redeem(s, %{"name" => "Helper"}, "10.1.1.2")

      assert %{"error" => "arbiter_role"} =
               conn |> phone(helper_token) |> get(base) |> json_response(403)

      stranger = user_scope_fixture()
      {:ok, %{secret: s2}} = Manubrium.create_connect_code(stranger, "http://test")
      {:ok, _, other} = Manubrium.redeem(s2, %{"name" => "Other"}, "10.1.1.3")

      assert %{"error" => "tournament_not_found"} =
               conn |> phone(other) |> get(base) |> json_response(404)
    end
  end

  describe "POST /hall/print" do
    test "asks the plugins to print, and says how many devices it reached", %{
      conn: conn,
      token: token,
      base: base
    } do
      FakePlugin.register(hall_command: {:ok, 2}, hall_notify: self())

      answer =
        conn
        |> phone(token)
        |> post(base <> "/print", %{"what" => "standings"})
        |> json_response(200)

      assert answer["sent_to"] == 2
      assert_received {:hall_command, {:print, "standings"}}
      assert_valid!("manubrium-v1", "hall-command-response.schema.json", answer)
    end

    test "0 devices is an answer, not an error", %{conn: conn, token: token, base: base} do
      FakePlugin.register(hall_command: {:ok, 0})

      answer =
        conn |> phone(token) |> post(base <> "/print", %{"what" => "both"}) |> json_response(200)

      assert answer["sent_to"] == 0
    end

    test "a word nobody prints is a 400 and the plugins hear nothing", %{
      conn: conn,
      token: token,
      base: base
    } do
      FakePlugin.register(hall_command: {:ok, 1}, hall_notify: self())

      assert %{"error" => "bad_request"} =
               conn
               |> phone(token)
               |> post(base <> "/print", %{"what" => "certificates"})
               |> json_response(400)

      assert %{"error" => "bad_request"} =
               conn |> phone(token) |> post(base <> "/print", %{}) |> json_response(400)

      refute_received {:hall_command, _}
    end

    test "no hall app at all is hall_off; no published round is hall_no_round", %{
      conn: conn,
      token: token,
      base: base
    } do
      assert %{"error" => "hall_off"} =
               conn
               |> phone(token)
               |> post(base <> "/print", %{"what" => "both"})
               |> json_response(409)

      FakePlugin.register(hall_command: {:error, :no_round})

      assert %{"error" => "hall_no_round"} =
               conn
               |> phone(token)
               |> post(base <> "/print", %{"what" => "both"})
               |> json_response(409)
    end

    test "standings that may not be printed, and any other refusal, are hall_failed", %{
      conn: conn,
      token: token,
      base: base
    } do
      FakePlugin.register(hall_command: {:error, :no_standings})

      assert %{"error" => "hall_failed", "message" => message} =
               conn
               |> phone(token)
               |> post(base <> "/print", %{"what" => "standings"})
               |> json_response(409)

      assert message =~ "standings"

      FakePlugin.register(hall_command: {:error, :surprise})

      assert %{"error" => "hall_failed"} =
               conn
               |> phone(token)
               |> post(base <> "/print", %{"what" => "both"})
               |> json_response(409)
    end
  end

  describe "POST /hall/countdown" do
    test "a length the page offers starts it and answers with the countdown that runs", %{
      conn: conn,
      token: token,
      base: base
    } do
      FakePlugin.register(
        hall_command: {:ok, 1},
        hall_notify: self(),
        hall_status: %{app: "nunki", devices: [], countdown: %{round: 1, seconds_left: 300}}
      )

      answer =
        conn
        |> phone(token)
        |> post(base <> "/countdown", %{"minutes" => 5})
        |> json_response(200)

      assert_received {:hall_command, {:countdown, 5}}
      assert %{"sent_to" => 1, "countdown" => %{"round" => 1, "seconds_left" => 300}} = answer
      assert_valid!("manubrium-v1", "hall-command-response.schema.json", answer)
    end

    test "cancel answers with no countdown", %{conn: conn, token: token, base: base} do
      FakePlugin.register(hall_command: {:ok, 1}, hall_notify: self())

      answer =
        conn
        |> phone(token)
        |> post(base <> "/countdown", %{"cancel" => true})
        |> json_response(200)

      assert_received {:hall_command, :cancel_countdown}
      assert answer["countdown"] == nil
      assert_valid!("manubrium-v1", "hall-command-response.schema.json", answer)
    end

    test "a length it does not offer is a 400", %{conn: conn, token: token, base: base} do
      FakePlugin.register(hall_command: {:ok, 1}, hall_notify: self())

      for body <- [%{"minutes" => 7}, %{"minutes" => "5"}, %{"cancel" => false}, %{}] do
        assert %{"error" => "bad_request"} =
                 conn |> phone(token) |> post(base <> "/countdown", body) |> json_response(400)
      end

      refute_received {:hall_command, _}
    end
  end

  describe "POST /hall/announce" do
    test "a canned announcement", %{conn: conn, token: token, base: base} do
      FakePlugin.register(hall_command: {:ok, 3}, hall_notify: self())

      answer =
        conn
        |> phone(token)
        |> post(base <> "/announce", %{"canned" => "silence"})
        |> json_response(200)

      assert answer["sent_to"] == 3
      assert_received {:hall_command, {:announce, "silence", nil}}
    end

    test "free text is trimmed and cut at 300 characters", %{conn: conn, token: token, base: base} do
      FakePlugin.register(hall_command: {:ok, 1}, hall_notify: self())
      long = String.duplicate("a", 400)

      conn
      |> phone(token)
      |> post(base <> "/announce", %{"text" => "  Boards 1-5 to the desk  "})
      |> json_response(200)

      assert_received {:hall_command, {:announce, nil, "Boards 1-5 to the desk"}}

      conn |> phone(token) |> post(base <> "/announce", %{"text" => long}) |> json_response(200)
      assert_received {:hall_command, {:announce, nil, text}}
      assert String.length(text) == 300
    end

    test "nothing to say, or a canned key nobody knows, is a 400", %{
      conn: conn,
      token: token,
      base: base
    } do
      FakePlugin.register(hall_command: {:ok, 1}, hall_notify: self())

      for body <- [%{}, %{"text" => "   "}, %{"canned" => "fire"}] do
        assert %{"error" => "bad_request"} =
                 conn |> phone(token) |> post(base <> "/announce", body) |> json_response(400)
      end

      refute_received {:hall_command, _}
    end
  end

  describe "the request examples of the contract" do
    test "every one is taken by the endpoint it is for", %{conn: conn, token: token, base: base} do
      FakePlugin.register(hall_command: {:ok, 1})

      for {file, path} <- [
            {"hall-reprint-request.json", "/print"},
            {"hall-countdown-request.json", "/countdown"},
            {"hall-countdown-request.cancel.json", "/countdown"},
            {"hall-announce-request.json", "/announce"},
            {"hall-announce-request.text.json", "/announce"}
          ] do
        body = example("manubrium-v1", file)

        assert_valid!(
          "manubrium-v1",
          String.replace(file, ~r/(\.[a-z-]+)?\.json$/, ".schema.json"),
          body
        )

        assert conn |> phone(token) |> post(base <> path, body) |> json_response(200), file
      end
    end
  end
end
