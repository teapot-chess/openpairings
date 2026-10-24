defmodule PairingsEngine.TeamTpn do
  @moduledoc """
  A team Swiss's team numbers corrected by the arbiter without touching a
  rating: an exchange between two teams of equal team rating, and a
  regeneration from the current team ratings. The team counterpart of
  `PairingsEngine.Tpn`, on the same terms (C.04.2 Art. 2.3, which C.04.6 Art.
  1.1 adopts for team numbers): allowed only until round 4 is paired, never in
  a team round robin, whose Berger table was drawn over the numbers.

  ## What a team's rating is

  The one the Teams page shows and the order of the teams is made by:
  `Tournaments.team_rating/3` by the tournament's *Team rating for the order
  of the teams* (or the rating typed on the card). Compared as the whole
  number it displays, so two teams show the same figure or they do not.

  ## The numbers

  `teams.pairing_number`, issued when round 1 is paired
  (`PairingsEngine.TeamSwiss`). Before round 1 the order
  is the Teams page's own (arrows, *Order by rating*) and nothing here
  applies. Matches are stored by team, not by number, so renumbering rewrites
  no game; rounds already paired were paired with the old numbers, and the
  dialog says so. `teams.seed` follows the number, so the Teams page lists
  the teams the way the pairing now numbers them.

  ## A regeneration

  Every numbered team is sorted by team rating, highest first; teams of equal
  rating keep the order they had, so an exchange survives it. Then numbered
  1..N. A regeneration of numbers that already follow the ratings writes
  nothing and answers `{:unchanged, order}`.

  None of this is a pairing setting: it never touches
  `fide_compliance_lost_round`, so the tournament stays in FIDE mode.
  """

  import Ecto.Query

  alias PairingsEngine.Pairing, as: Engine
  alias PairingsEngine.{Repo, Tournaments}
  alias PairingsEngine.Tournaments.{Team, Tournament}

  # C.04.2: the numbers may be corrected only before round 4 is paired.
  @last_round_before_lock 3

  @doc "Whether this is a tournament whose team numbers can be corrected at all: a team Swiss."
  def applies?(%Tournament{} = t), do: Tournament.team_swiss?(t)

  @doc """
  Whether they can be corrected now: a team Swiss with at least one round and
  at most three paired.
  """
  def editable?(%Tournament{} = t) do
    paired = Engine.paired_rounds_count(t.id)
    applies?(t) and paired >= 1 and paired <= @last_round_before_lock
  end

  @doc "The numbering as it stands, `[{team, number}]` in number order (numbered teams only)."
  def order(%Tournament{} = t) do
    t.id
    |> Tournaments.list_teams()
    |> Enum.filter(&is_integer(&1.pairing_number))
    |> Enum.sort_by(&{&1.pairing_number, &1.id})
    |> Enum.map(&{&1, &1.pairing_number})
  end

  @doc "A team's rating as the comparison reads it: the whole number it displays, 0 for none."
  def rating(%Tournament{} = t, %Team{} = team), do: round(Tournaments.team_rating(t, team))

  @doc """
  The teams whose number is not the one their rating earns, while that can
  still be corrected: `[%{team, rating, number, expected}]` in number order.
  Teams of equal rating in any order are never reported - that is what an
  exchange is for.
  """
  def out_of_place(%Tournament{} = t) do
    if editable?(t), do: t |> order() |> misplaced(t), else: []
  end

  @doc """
  What a regeneration would change, `[{team, old_number, new_number}]` - the
  teams whose number moves, in new-number order.
  """
  def regeneration_changes(%Tournament{} = t) do
    current = order(t)

    t
    |> regenerated(current)
    |> Enum.with_index(1)
    |> Enum.reject(fn {team, n} -> team.pairing_number == n end)
    |> Enum.map(fn {team, n} -> {team, team.pairing_number, n} end)
  end

  @doc """
  Exchanges the numbers of two teams of the same rating. Refused:
  `{:error, :different_ratings}`, `{:error, :locked}` (round 4 paired, or no
  round yet), `{:error, :not_swiss}`, `{:error, :not_found}`.
  Returns `{:ok, order}`.
  """
  def exchange(%Tournament{} = t, a_id, b_id) do
    with :ok <- guard(t) do
      teams = Map.new(order(t), fn {team, _n} -> {team.id, team} end)

      case {Map.get(teams, a_id), Map.get(teams, b_id)} do
        {%Team{} = a, %Team{} = b} when a_id != b_id ->
          if rating(t, a) == rating(t, b),
            do: do_exchange(t, a, b),
            else: {:error, :different_ratings}

        _ ->
          {:error, :not_found}
      end
    end
  end

  defp do_exchange(t, a, b) do
    ids = Enum.map(order(t), fn {team, _n} -> team.id end)

    swapped =
      Enum.map(ids, fn
        id when id == a.id -> b.id
        id when id == b.id -> a.id
        id -> id
      end)

    case write(t, swapped) do
      :written -> {:ok, order(t)}
      :unchanged -> {:unchanged, order(t)}
    end
  end

  @doc """
  Regenerates the numbers from the current team ratings, keeping the order of
  equal ratings. Refused like `exchange/3`. `{:ok, order}`, or
  `{:unchanged, order}` when every number already follows the ratings.
  """
  def regenerate(%Tournament{} = t) do
    with :ok <- guard(t) do
      case write(t, Enum.map(regenerated(t, order(t)), & &1.id)) do
        :written -> {:ok, order(t)}
        :unchanged -> {:unchanged, order(t)}
      end
    end
  end

  defp regenerated(t, current) do
    current
    |> Enum.sort_by(fn {team, n} -> {-rating(t, team), n} end)
    |> Enum.map(fn {team, _n} -> team end)
  end

  # Over the same set of numbers, sorted by rating (ties by held number): who
  # does not land on their own number is out of place.
  defp misplaced(rows, t) do
    slots = rows |> Enum.map(&elem(&1, 1)) |> Enum.sort()

    rows
    |> Enum.sort_by(fn {team, n} -> {-rating(t, team), n} end)
    |> Enum.zip(slots)
    |> Enum.reject(fn {{_team, n}, slot} -> n == slot end)
    |> Enum.map(fn {{team, n}, slot} ->
      %{team: team, rating: rating(t, team), number: n, expected: slot}
    end)
    |> Enum.sort_by(& &1.number)
  end

  # Numbers `ids` 1..N. `:unchanged`, and no write and no broadcast, when
  # every team holds that number already. The seed follows the number.
  defp write(t, ids) do
    wanted = Enum.with_index(ids, 1)

    held =
      Repo.all(from x in Team, where: x.tournament_id == ^t.id, select: {x.id, x.pairing_number})
      |> Map.new()

    if Enum.all?(wanted, fn {id, number} -> Map.get(held, id) == number end) do
      :unchanged
    else
      Repo.transaction(fn ->
        Enum.each(wanted, fn {id, number} ->
          Repo.update_all(
            from(x in Team, where: x.id == ^id and x.tournament_id == ^t.id),
            set: [pairing_number: number, seed: number]
          )
        end)
      end)

      Tournaments.broadcast_tournament_change(t.id, :players)
      :written
    end
  end

  defp guard(t) do
    cond do
      refusal = Tournaments.write_refused(t.id) -> refusal
      not applies?(t) -> {:error, :not_swiss}
      not editable?(t) -> {:error, :locked}
      true -> :ok
    end
  end
end
