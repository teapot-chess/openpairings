defmodule PairingsEngine.TournamentSeriesTest do
  # async: false, like the groups tests: SQLite has one writer.
  use PairingsEngine.DataCase, async: false

  import Ecto.Query
  alias PairingsEngine.{Audit, Repo, Snapshot, TournamentExport, TournamentImport}
  alias PairingsEngine.{TournamentSeries, Tournaments}
  alias PairingsEngine.Accounts.{Scope, User}
  alias PairingsEngine.Tournaments.Tournament

  defp user_scope do
    user =
      Repo.insert!(%User{
        email: "user#{System.unique_integer([:positive])}@example.com",
        confirmed_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    Scope.for_user(user)
  end

  defp tournament(scope, name, start_date \\ "") do
    {:ok, t} =
      Tournaments.create_tournament(scope, %{
        "name" => name,
        "type" => "swiss",
        "rounds_count" => "5"
      })

    # Derived from the round dates in real life; set straight here.
    Repo.update_all(from(x in Tournament, where: x.id == ^t.id), set: [start_date: start_date])
    %{t | start_date: start_date}
  end

  defp reload(%{id: id}), do: Tournaments.get_tournament!(id)

  setup do
    scope = user_scope()
    e25 = tournament(scope, "Open Brugge", "2025-03-01")
    e26 = tournament(scope, "Open Brugge", "01/03/2026")
    %{scope: scope, e25: e25, e26: e26}
  end

  describe "the snapshot" do
    test "carries series_id when set and omits the key when not", %{scope: scope, e25: e25} do
      refute Map.has_key?(Snapshot.build(e25)["tournament"], "series_id")

      {:ok, started} = TournamentSeries.start_series(scope, e25)
      assert started.series_id =~ ~r/\A[A-Za-z0-9_-]{6,64}\z/
      assert Snapshot.build(reload(e25))["tournament"]["series_id"] == started.series_id

      {:ok, _} = TournamentSeries.leave_series(scope, started)
      refute Map.has_key?(Snapshot.build(reload(e25))["tournament"], "series_id")
    end
  end

  describe "start, join, leave" do
    test "joining a tournament with no series mints one on both", %{
      scope: scope,
      e25: e25,
      e26: e26
    } do
      {:ok, joined} = TournamentSeries.join_series(scope, e26, e25.id)

      assert joined.series_id
      assert reload(e25).series_id == joined.series_id
      assert reload(e26).series_id == joined.series_id
    end

    test "joining a tournament that has a series takes that one", %{
      scope: scope,
      e25: e25,
      e26: e26
    } do
      {:ok, started} = TournamentSeries.start_series(scope, e25)
      {:ok, joined} = TournamentSeries.join_series(scope, e26, e25.id)
      assert joined.series_id == started.series_id
    end

    test "editions lists the other editions with their year", %{
      scope: scope,
      e25: e25,
      e26: e26
    } do
      {:ok, _} = TournamentSeries.join_series(scope, e26, e25.id)

      assert [%{id: id, year: 2025}] = TournamentSeries.editions(scope, reload(e26))
      assert id == e25.id
      assert [%{id: id26, year: 2026}] = TournamentSeries.editions(scope, reload(e25))
      assert id26 == e26.id
      assert TournamentSeries.editions(scope, %{reload(e25) | series_id: nil}) == []
    end

    test "candidates are the other tournaments the user may edit, series flagged", %{
      scope: scope,
      e25: e25,
      e26: e26
    } do
      assert [%{id: id, year: 2026, same_series?: false}] =
               TournamentSeries.candidates(scope, e25)

      assert id == e26.id
      {:ok, _} = TournamentSeries.join_series(scope, e26, e25.id)
      assert [%{same_series?: true}] = TournamentSeries.candidates(scope, reload(e25))
    end

    test "leaving clears the id and leaves the others alone", %{
      scope: scope,
      e25: e25,
      e26: e26
    } do
      {:ok, _} = TournamentSeries.join_series(scope, e26, e25.id)
      {:ok, left} = TournamentSeries.leave_series(scope, reload(e26))

      assert left.series_id == nil
      assert reload(e25).series_id
    end

    test "each change is audited", %{scope: scope, e25: e25} do
      {:ok, _} = TournamentSeries.start_series(scope, e25)

      assert Enum.any?(
               Audit.list_for_tournament(e25.id),
               &(&1.action == "tournament.series_changed")
             )
    end
  end

  describe "authorization" do
    test "someone else's tournament can neither be changed nor joined", %{
      scope: scope,
      e25: e25,
      e26: e26
    } do
      stranger = user_scope()

      assert {:error, :not_authorized} = TournamentSeries.start_series(stranger, e25)
      assert {:error, :not_authorized} = TournamentSeries.leave_series(stranger, e25)

      # Own tournament, somebody else's target: refused, and nothing minted.
      mine = tournament(stranger, "Mine")
      assert {:error, :not_authorized} = TournamentSeries.join_series(stranger, mine, e25.id)
      assert {:error, :not_authorized} = TournamentSeries.join_series(scope, e26, 0)
      assert reload(e25).series_id == nil
      assert reload(mine).series_id == nil
    end

    test "editions and candidates show only what the viewer may open", %{
      scope: scope,
      e25: e25,
      e26: e26
    } do
      {:ok, _} = TournamentSeries.join_series(scope, e26, e25.id)
      stranger = user_scope()

      assert TournamentSeries.editions(stranger, reload(e26)) == []
      assert TournamentSeries.candidates(stranger, reload(e26)) == []
    end

    test "an archived tournament is read-only", %{scope: scope, e25: e25, e26: e26} do
      Repo.update_all(
        from(t in Tournament, where: t.id == ^e25.id),
        set: [archived_at: DateTime.truncate(DateTime.utc_now(), :second)]
      )

      assert {:error, :archived} = TournamentSeries.start_series(scope, e25)
      assert {:error, :archived} = TournamentSeries.join_series(scope, e26, e25.id)
      assert TournamentSeries.candidates(scope, e26) == []
    end

    test "a tournament cannot join itself", %{scope: scope, e25: e25} do
      assert {:error, :same_tournament} = TournamentSeries.join_series(scope, e25, e25.id)
    end
  end

  describe "export and import" do
    test "the series id survives a round trip", %{scope: scope, e25: e25} do
      {:ok, started} = TournamentSeries.start_series(scope, e25)

      envelope = e25 |> reload() |> TournamentExport.export_tournament()
      [%{"tournament" => %{"series_id" => id}}] = envelope["tournaments"]
      assert id == started.series_id

      {:ok, [copy]} =
        envelope |> Jason.encode!() |> Jason.decode!() |> TournamentImport.import(scope)

      assert copy.series_id == started.series_id
    end

    test "a malformed series id in a file is dropped", %{scope: scope, e25: e25} do
      envelope =
        e25
        |> TournamentExport.export_tournament()
        |> put_in(["tournaments", Access.at(0), "tournament", "series_id"], "no spaces allowed")

      {:ok, [copy]} = TournamentImport.import(envelope, scope)
      assert copy.series_id == nil
    end
  end
end
