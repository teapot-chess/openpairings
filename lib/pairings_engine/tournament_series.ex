defmodule PairingsEngine.TournamentSeries do
  @moduledoc """
  Tournament series: the same event in other years - Open Brugge 2025, Open
  Brugge 2026 - so the results site can offer "Other editions" on each one.

  This is not `PairingsEngine.TournamentGroups`. A group is several sections
  of ONE event (the Open, the U12) and has tables, a name and an order. A
  series is only a shared id, `tournaments.series_id`, and nothing else:
  there is no series row, no owner, no label, no order. Two tournaments are
  in the same series when their ids are equal.

  ## Who may do what

  Every right comes from the tournaments involved. Starting, leaving, or
  joining a series needs you to be allowed to edit that tournament
  (`Tournaments.get_authorized_tournament/2`), and an archived or handed-off
  one is read-only here as everywhere (`Tournaments.ensure_writable/1`).
  Joining the series of ANOTHER tournament needs you to be allowed to edit
  that one as well, so nobody can attach their tournament to a stranger's by
  guessing; if it has no series yet, it gets one minted on the spot, and
  both are in it.

  ## What anybody sees

  Only what they could open anyway. `editions/2` and `candidates/2` list
  tournaments the viewer may open; another arbiter's edition of the same
  series is not mentioned, not even as a count.

  ## On the results site

  The snapshot carries just `series_id` (`PairingsEngine.Snapshot`), never
  the name of another edition. The results site looks up the other editions
  it holds itself, from the same publisher and visible ones only. Every
  change here goes through `Tournaments.broadcast_tournament_change/2`,
  which also queues the publish, so the page that says "Other editions"
  catches up without anybody remembering to ask.
  """

  import Ecto.Query

  alias PairingsEngine.{Audit, Repo, Tournaments}
  alias PairingsEngine.Accounts.Scope
  alias PairingsEngine.Tournaments.Tournament

  @doc "A fresh random series id (72 bits, url-safe; the contract wants 6 to 64 of `[A-Za-z0-9_-]`)."
  def generate_series_id, do: :crypto.strong_rand_bytes(9) |> Base.encode16(case: :lower)

  ## ---------- reading ----------

  @doc """
  The OTHER editions of `tournament`'s series that `scope`'s user may open,
  oldest first, each as `%{id, name, year}`. Empty for a tournament in no
  series.
  """
  def editions(%Scope{} = scope, %Tournament{series_id: series_id, id: id})
      when is_binary(series_id) do
    Repo.all(
      from t in Tournament,
        where:
          t.series_id == ^series_id and t.id != ^id and
            t.id in subquery(Tournaments.authorized_tournament_ids(scope))
    )
    |> sort_and_label()
  end

  def editions(_scope, _tournament), do: []

  @doc """
  The tournaments `tournament` could be put in a series with: every other
  one `scope`'s user may edit (and that is not archived or handed off, since
  joining may write to it), as `%{id, name, year, same_series?}`.
  """
  def candidates(%Scope{} = scope, %Tournament{id: id, series_id: series_id}) do
    Repo.all(
      from t in Tournament,
        where:
          t.id != ^id and is_nil(t.archived_at) and is_nil(t.handed_off_at) and
            t.id in subquery(Tournaments.authorized_tournament_ids(scope))
    )
    |> sort_and_label()
    |> Enum.map(fn c ->
      Map.put(c, :same_series?, series_id != nil and c.series_id == series_id)
    end)
  end

  defp sort_and_label(tournaments) do
    tournaments
    |> Enum.map(fn t ->
      %{id: t.id, name: t.name, year: year(t), series_id: t.series_id, sort: sort_key(t)}
    end)
    |> Enum.sort_by(& &1.sort)
    |> Enum.map(&Map.delete(&1, :sort))
  end

  # The start date is typed by a person in whatever order their country
  # writes it, so the year is the first run of four digits in it.
  defp year(%Tournament{start_date: start_date, inserted_at: inserted_at}) do
    case Regex.run(~r/\d{4}/, start_date || "") do
      [year] -> String.to_integer(year)
      nil -> inserted_at.year
    end
  end

  defp sort_key(%Tournament{} = t), do: {year(t), t.name, t.id}

  ## ---------- writing ----------

  @doc """
  Puts `tournament` in a series of its own, leaving the one it was in.
  """
  def start_series(%Scope{} = scope, %Tournament{} = tournament) do
    with {:ok, tournament} <- editable(scope, tournament) do
      set(scope, tournament, generate_series_id(), [])
    end
  end

  @doc """
  Puts `tournament` in the series of tournament `other_id`, which the user
  must be allowed to edit as well. When that one has no series yet, one is
  minted and both end up in it. Joining the series it is already in changes
  nothing.
  """
  def join_series(%Scope{} = scope, %Tournament{} = tournament, other_id) do
    with {:ok, tournament} <- editable(scope, tournament),
         {:ok, other} <- editable(scope, other_id),
         :ok <- different(tournament, other) do
      case other.series_id do
        nil ->
          series_id = generate_series_id()

          with {:ok, other} <- write(other, series_id) do
            set(scope, tournament, series_id, [other])
          end

        series_id when series_id == tournament.series_id ->
          {:ok, tournament}

        series_id ->
          set(scope, tournament, series_id, [])
      end
    end
  end

  @doc """
  Takes `tournament` out of its series. The others keep theirs: a series of
  one is harmless, and the results site shows nothing for it.
  """
  def leave_series(%Scope{} = scope, %Tournament{} = tournament) do
    with {:ok, tournament} <- editable(scope, tournament) do
      if tournament.series_id, do: set(scope, tournament, nil, []), else: {:ok, tournament}
    end
  end

  # Writes `series_id` on `tournament` and tells everyone, `also` being other
  # tournaments already written in the same act (the one a join minted an id on).
  defp set(scope, tournament, series_id, also) do
    previous = tournament.series_id

    with {:ok, updated} <- write(tournament, series_id) do
      Audit.log(updated.id, scope, "tournament.series_changed", %{
        from: previous,
        to: series_id,
        with: Enum.map(also, & &1.id)
      })

      for t <- also do
        Audit.log(t.id, scope, "tournament.series_changed", %{
          from: nil,
          to: series_id,
          with: [updated.id]
        })

        Tournaments.broadcast_tournament_change(t.id, :settings)
      end

      Tournaments.broadcast_tournament_change(updated.id, :settings)
      {:ok, updated}
    end
  end

  defp write(%Tournament{} = tournament, series_id) do
    tournament |> Ecto.Changeset.change(series_id: series_id) |> Repo.update()
  end

  defp editable(scope, id) when is_integer(id), do: editable(scope, %Tournament{id: id})

  defp editable(scope, %Tournament{id: id}) do
    case Tournaments.get_authorized_tournament(scope, id) do
      nil ->
        {:error, :not_authorized}

      tournament ->
        case Tournaments.ensure_writable(tournament) do
          :ok -> {:ok, tournament}
          error -> error
        end
    end
  end

  defp different(%Tournament{id: id}, %Tournament{id: id}), do: {:error, :same_tournament}
  defp different(_a, _b), do: :ok
end
