defmodule PairingsEngine.CustomTiebreakTest do
  @moduledoc """
  The tournament's own tie-break (`CUSTOM`): a weighted sum of per-player
  figures, both ways round. The formula is data, the standings rank on it
  where the list puts it, FIDE mode locks it with the list, it travels with
  the tournament export, and it never reaches a TRF tie-break line.
  """
  use PairingsEngine.DataCase, async: false

  alias PairingsEngine.{
    Compliance,
    Pairing,
    Repo,
    Snapshot,
    Standings,
    Tiebreaks,
    TournamentExport,
    TournamentImport,
    Tournaments,
    TrfExport
  }

  alias PairingsEngine.Tiebreaks.Custom
  alias PairingsEngine.Tournaments.Tournament

  @forfeits_lost Custom.preset("forfeits_lost")

  # Results by board index: a forfeit every few boards, so some players
  # collect them and others do not.
  @results ~w(1-0 0-1FF 1/2-1/2 1-0FF 0-1)

  defp played(tiebreaks, formula, attrs \\ %{}) do
    t =
      Repo.insert!(
        struct(
          Tournament,
          Map.merge(
            %{
              name: "Custom",
              type: "swiss",
              rounds_count: 3,
              tiebreaks: tiebreaks,
              custom_tiebreak: formula,
              round_dates: for(r <- 1..3, do: "2026-09-0#{r}")
            },
            attrs
          )
        )
      )

    for i <- 1..10 do
      {:ok, _} =
        Tournaments.create_player(t.id, %{
          tournament_id: t.id,
          name: "Player #{i}",
          fide_rating: 2400 - 37 * i
        })
    end

    for _ <- 1..3 do
      {:ok, round} = Pairing.pair_next_round(Repo.reload!(t), [])
      round = Tournaments.get_round(t.id, round.number)

      for {p, i} <- Enum.with_index(round.pairings), p.black_player_id do
        {:ok, _} =
          Tournaments.update_pairing_result(p, Enum.at(@results, rem(i + round.number, 5)))
      end
    end

    Repo.reload!(t)
  end

  defp forfeit_losses(entry),
    do: Enum.count(entry.games, &((not &1.played and &1.opponent_id) && &1.outcome == :loss))

  describe "the formula" do
    test "a weighted sum, each term with its own sign" do
      formula = %{
        "direction" => "higher",
        "terms" => [
          %{"figure" => "wins", "sign" => "+", "weight" => 2.0},
          %{"figure" => "forfeit_losses", "sign" => "-", "weight" => 1.5}
        ]
      }

      {total, parts} = Custom.evaluate(formula, %{"wins" => 3, "forfeit_losses" => 2})
      assert total == 3.0
      assert Enum.map(parts, & &1.value) == [6.0, -3.0]
      assert Custom.working_text(parts, total) =~ "2 × Wins over the board (3)"
      assert Custom.working_text(parts, total) =~ "= 3"
    end

    test "both directions: higher first, or lower first" do
      higher = %{"direction" => "higher", "terms" => []}
      lower = %{"direction" => "lower", "terms" => []}

      assert Enum.sort_by([1.0, 3.0, 2.0], &Custom.sort_key(&1, higher)) == [3.0, 2.0, 1.0]
      assert Enum.sort_by([1.0, 3.0, 2.0], &Custom.sort_key(&1, lower)) == [1.0, 2.0, 3.0]
    end

    test "the default is the sensible one: minus forfeit losses, higher is better" do
      assert Custom.default() == @forfeits_lost

      assert %{
               "direction" => "higher",
               "terms" => [%{"figure" => "forfeit_losses", "sign" => "-"}]
             } = Custom.default()

      assert %{"terms" => [%{"figure" => "forfeit_wins", "sign" => "+"}]} =
               Custom.preset("forfeits_won")

      assert %{"terms" => []} = Custom.preset("custom")

      for id <- Custom.preset_ids() do
        {name, explanation} = Custom.preset_text(id)
        assert name != "" and String.length(explanation) > 60
      end
    end

    test "normalising keeps only data: unknown figures, signs and weights go" do
      formula =
        Custom.normalize(%{
          "direction" => "sideways",
          "preset" => "File.rm_rf!(\"/\")",
          "terms" => %{
            "0" => %{"figure" => "System.halt()", "sign" => "+", "weight" => "1"},
            "1" => %{"figure" => "wins", "sign" => "*", "weight" => "1"},
            "2" => %{"figure" => "wins", "sign" => "-", "weight" => "1e9"},
            "3" => %{"figure" => "draws", "sign" => "-", "weight" => "0,5"}
          }
        })

      assert formula == %{
               "preset" => "custom",
               "direction" => "higher",
               "terms" => [%{"figure" => "draws", "sign" => "-", "weight" => 0.5}]
             }

      assert Custom.normalize("1 + 1") == nil
      refute Custom.usable?(Custom.normalize(%{"terms" => []}))
    end

    test "the figures come from the game records" do
      t = %{points_win: 1.0, points_draw: 0.5}

      games = [
        %{played: true, opponent_id: 1, outcome: :win, colour: :b, bye_type: nil, points: 1.0},
        %{played: true, opponent_id: 2, outcome: :draw, colour: :w, bye_type: nil, points: 0.5},
        %{played: false, opponent_id: 3, outcome: :loss, colour: :w, bye_type: nil, points: 0.0},
        %{played: false, opponent_id: 4, outcome: :win, colour: :b, bye_type: nil, points: 1.0},
        %{
          played: false,
          opponent_id: nil,
          outcome: :none,
          colour: nil,
          bye_type: "pairing-allocated",
          points: 1.0
        },
        %{
          played: false,
          opponent_id: nil,
          outcome: :none,
          colour: nil,
          bye_type: "requested-half",
          points: 0.5
        }
      ]

      f = Custom.figures_for(%{games: games, points: 4.0, completed_rounds: 7}, t)

      assert f["wins"] == 1
      assert f["draws"] == 1
      assert f["games"] == 2
      assert f["forfeit_losses"] == 1
      assert f["forfeit_wins"] == 1
      assert f["pab"] == 1
      assert f["half_byes"] == 1
      assert f["full_byes"] == 0
      assert f["black_games"] == 1
      assert f["black_wins"] == 1
      assert f["unplayed"] == 5
      assert f["points"] == 4.0
    end
  end

  describe "the catalogue" do
    test "an individual tie-break of the tournament's own" do
      assert %{code: "CUSTOM", scope: :individual} = Tiebreaks.get("CUSTOM")
      assert Tiebreaks.own?("CUSTOM")
      refute Tiebreaks.valid?("CUSTOM", "team-swiss")
      assert Tiebreaks.custom_above_fide?(~w(CUSTOM BH))
      refute Tiebreaks.custom_above_fide?(~w(BH CUSTOM))
      refute Tiebreaks.custom_above_fide?(~w(EXT CUSTOM))
    end
  end

  describe "the standings" do
    test "fewer forfeits lost ranks higher among players level on points" do
      t = played(["CUSTOM"], @forfeits_lost)
      entries = Standings.standings(t)

      for e <- entries, do: assert(e.tiebreaks["CUSTOM"] == -forfeit_losses(e) * 1.0)
      assert Enum.any?(entries, &(&1.tiebreaks["CUSTOM"] < 0))

      for {_points, group} <- Enum.group_by(entries, & &1.points) do
        values = Enum.map(group, & &1.tiebreaks["CUSTOM"])
        assert values == Enum.sort(values, :desc)
      end
    end

    test "the other way round: lower is better puts the most forfeits lost first" do
      t = played(["CUSTOM"], Map.put(@forfeits_lost, "direction", "lower"))

      for {_points, group} <- Enum.group_by(Standings.standings(t), & &1.points) do
        values = Enum.map(group, & &1.tiebreaks["CUSTOM"])
        assert values == Enum.sort(values, :asc)
      end
    end

    test "every entry carries its working" do
      t = played(["CUSTOM"], @forfeits_lost)

      for e <- Standings.standings(t) do
        assert [%{figure: "forfeit_losses", sign: "-", count: count}] = e.custom_working
        assert count == forfeit_losses(e)
      end
    end

    test "a figure read from a C.07 tie-break works without it being on the list" do
      formula = %{"terms" => [%{"figure" => "bh", "sign" => "+", "weight" => 1}]}
      t = played(["CUSTOM"], formula)
      with_bh = played(["CUSTOM", "BH"], formula)

      values = Map.new(Standings.standings(with_bh), &{&1.player.name, &1.tiebreaks["BH"]})

      for e <- Standings.standings(t),
          do: assert(e.tiebreaks["CUSTOM"] == values[e.player.name])
    end

    test "an empty formula is dropped, not a column of noughts" do
      t = played(["CUSTOM", "BH"], Custom.preset("custom"))
      assert {"CUSTOM", :not_calculable} in Standings.dropped_tiebreaks_with_reasons(t)
    end
  end

  describe "FIDE mode" do
    test "it does not leave FIDE mode, and the formula locks with the list" do
      t = played(["BH", "CUSTOM"], @forfeits_lost)
      assert Compliance.fide_mode?(t)
      assert :custom_tiebreak in Tournaments.fide_locked_fields(t)

      reversed = Map.put(@forfeits_lost, "direction", "lower")

      assert {:error, :locked_in_fide_mode} =
               Tournaments.update_tournament(t, %{"custom_tiebreak" => reversed})

      # The same formula sent back unchanged is not a change.
      assert {:ok, _} = Tournaments.update_tournament(t, %{"custom_tiebreak" => @forfeits_lost})
    end
  end

  describe "files" do
    test "the export carries the formula and the import brings it back", %{} do
      t = played(["BH", "CUSTOM"], Custom.preset("forfeits_won"))
      user = PairingsEngine.AccountsFixtures.user_fixture()
      scope = PairingsEngine.Accounts.Scope.for_user(user)

      data = t |> TournamentExport.export_tournament() |> Jason.encode!() |> Jason.decode!()
      {:ok, [copy]} = TournamentImport.import(data, scope)

      assert copy.tiebreaks == ["BH", "CUSTOM"]
      assert copy.custom_tiebreak == Custom.preset("forfeits_won")
    end

    test "the TRF leaves it out of the tie-break line" do
      t = played(["BH", "CUSTOM", "SB"], @forfeits_lost)
      {:ok, text} = TrfExport.export(t)

      assert text =~ ~r/^202 BH,SB\s*$/m
      refute text =~ "CUSTOM"
    end

    test "the published standings name it as custom, and send no working for it" do
      t =
        played(["BH", "CUSTOM"], @forfeits_lost, %{
          standings_through: 3,
          public_display: %{"tiebreak_working" => true}
        })

      standings = Snapshot.build(t)["standings"]

      assert [%{"code" => "BH"}, %{"code" => "CUSTOM", "label" => label}] =
               standings["tiebreaks"]

      assert label =~ "not FIDE"
      assert label =~ "Forfeit losses"

      for row <- standings["rows"] do
        assert length(row["tiebreaks"]) == 2
        refute Map.has_key?(row["working"] || %{}, "CUSTOM")
      end

      hidden = Repo.update!(Ecto.Changeset.change(t, public_hidden_tiebreaks: ["CUSTOM"]))
      assert [%{"code" => "BH"}] = Snapshot.build(hidden)["standings"]["tiebreaks"]
    end
  end
end
