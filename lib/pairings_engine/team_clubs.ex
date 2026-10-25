defmodule PairingsEngine.TeamClubs do
  @moduledoc """
  The club of a team, for the "teams of the same club" rule
  (`PairingsEngine.Exclusions`, kind `team_club`).

  The rule reads `Team.club` and a blank club is never a group, so a team
  entered without one is silently outside the rule. This module is what lets
  the pages say so: which teams those are, and - from the clubs of the
  players on the roster - which club the team most likely plays for.

  A suggestion is only ever offered. Nothing here writes a club on its own:
  `apply_suggestion/4` runs when the arbiter presses the button.
  """

  alias PairingsEngine.{Audit, Tournaments}
  alias PairingsEngine.Tournaments.{Player, Team, Tournament}

  # At least this share of the players who HAVE a club must name the same
  # one (case-insensitive, trimmed), and there must be two such players.
  @share_numerator 3
  @share_denominator 4
  @min_players 2

  @doc """
  Whether the tournament has a rule of `kind` (`"team_club"`, or `"club"` for
  players), hard or soft, that covers every club. A rule that names clubs is
  not counted: a team with no club is not in its way.
  """
  def rule_applies?(%Tournament{} = tournament, kind \\ "team_club") do
    tournament.id
    |> Tournaments.list_pairing_rules()
    |> Enum.any?(&(&1.kind == kind and open?(&1)))
  end

  # A rule that lists club names only concerns those clubs; a team with no
  # club is not in the rule's way. Only the open rule ("every club") is.
  defp open?(%{names: names}), do: names in [nil, []]

  @doc "The teams whose club is empty (after trimming)."
  def without_club(teams), do: Enum.filter(teams, &blank?(&1.club))

  @doc """
  The club a team's players mostly share, or nil.

  Players with no club are left out of the count. Needs at least two players
  with a club, and at least three quarters of them on the same one, compared
  without regard to case or surrounding spaces. The answer is spelt the way
  most of those players spell it (the first alphabetically on a tie).
  """
  def suggest(players) do
    clubs =
      players
      |> Enum.map(&String.trim(club_of(&1)))
      |> Enum.reject(&(&1 == ""))

    total = length(clubs)

    with true <- total >= @min_players,
         {_key, group} <-
           clubs |> Enum.group_by(&String.downcase/1) |> Enum.max_by(fn {_k, g} -> length(g) end),
         true <- length(group) * @share_denominator >= total * @share_numerator do
      group
      |> Enum.frequencies()
      |> Enum.sort_by(fn {spelling, count} -> {-count, spelling} end)
      |> hd()
      |> elem(0)
    else
      _ -> nil
    end
  end

  @doc """
  `%{team_id => club}` for every team in `teams` that has no club and whose
  roster (`players`, anyone, filtered here by `team_id`) points at one.
  """
  def suggestions(teams, players) do
    by_team = Enum.group_by(players, & &1.team_id)

    for team <- without_club(teams),
        club = suggest(Map.get(by_team, team.id, [])),
        into: %{},
        do: {team.id, club}
  end

  @doc """
  Sets the club of a team, as the arbiter asked (a typed club or the suggested
  one), and audits it like the Teams page's own save.
  `{:ok, team}` or `{:error, reason}`.
  """
  def save(%Tournament{} = t, scope, %Team{} = team, club) when is_binary(club) do
    with {:ok, updated} <- Tournaments.update_team(team, %{"club" => club}) do
      Audit.log(t.id, scope, "team.updated", %{
        team_name: updated.name,
        previous_name: team.name,
        rating_override: updated.rating_override,
        club: updated.club
      })

      {:ok, updated}
    end
  end

  @doc """
  Presses the suggestion for `team`: worked out again from the roster now
  (never from what the page sent), refused with `{:error, :no_suggestion}`
  when there is none any more or the team has a club by now.
  """
  def apply_suggestion(%Tournament{} = t, scope, %Team{} = team) do
    players = t.id |> Tournaments.team_roster(team.id)

    with true <- blank?(team.club),
         club when is_binary(club) <- suggest(players) do
      save(t, scope, team, club)
    else
      _ -> {:error, :no_suggestion}
    end
  end

  @doc "The players of `players` with no club (after trimming)."
  def players_without_club(players), do: Enum.filter(players, &blank?(club_of(&1)))

  defp club_of(%Player{club: club}), do: club || ""
  defp club_of(%Team{club: club}), do: club || ""

  defp blank?(value), do: String.trim(value || "") == ""
end
