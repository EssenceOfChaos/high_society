defmodule HighSociety.Games.BattleshipTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.Battleship

  describe "parse_coord/1 and format_coord/1" do
    test "round-trip" do
      assert Battleship.parse_coord("A1") == {:ok, {0, 0}}
      assert Battleship.parse_coord("J10") == {:ok, {9, 9}}
      assert Battleship.parse_coord("B4") == {:ok, {1, 3}}
      assert Battleship.format_coord({0, 0}) == "A1"
      assert Battleship.format_coord({9, 9}) == "J10"
      assert Battleship.format_coord({1, 3}) == "B4"
    end

    test "rejects invalid input" do
      assert Battleship.parse_coord("K1") == :error
      assert Battleship.parse_coord("A11") == :error
      assert Battleship.parse_coord("A0") == :error
      assert Battleship.parse_coord("garbage") == :error
    end
  end

  describe "place_ship/4" do
    test "places a ship horizontally" do
      assert {:ok, [ship]} = Battleship.place_ship([], :destroyer, {0, 0}, :horizontal)
      assert ship.cells == [{0, 0}, {1, 0}]
    end

    test "places a ship vertically" do
      assert {:ok, [ship]} = Battleship.place_ship([], :destroyer, {0, 0}, :vertical)
      assert ship.cells == [{0, 0}, {0, 1}]
    end

    test "rejects an unknown ship type" do
      assert Battleship.place_ship([], :dinghy, {0, 0}, :horizontal) == {:error, :invalid_ship_type}
    end

    test "rejects a duplicate ship type" do
      {:ok, fleet} = Battleship.place_ship([], :destroyer, {0, 0}, :horizontal)
      assert Battleship.place_ship(fleet, :destroyer, {5, 5}, :horizontal) == {:error, :duplicate_ship_type}
    end

    test "rejects a run that leaves the board" do
      assert Battleship.place_ship([], :carrier, {8, 0}, :horizontal) == {:error, :out_of_bounds}
      assert Battleship.place_ship([], :carrier, {0, 8}, :vertical) == {:error, :out_of_bounds}
    end

    test "rejects an overlapping ship" do
      {:ok, fleet} = Battleship.place_ship([], :destroyer, {0, 0}, :horizontal)
      assert Battleship.place_ship(fleet, :submarine, {1, 0}, :vertical) == {:error, :overlaps}
    end
  end

  describe "fleet_complete?/1 and random_fleet/0" do
    test "is false until all 5 ship types are placed" do
      refute Battleship.fleet_complete?([])
      {:ok, fleet} = Battleship.place_ship([], :destroyer, {0, 0}, :horizontal)
      refute Battleship.fleet_complete?(fleet)
    end

    test "random_fleet/0 always produces a complete, non-overlapping, in-bounds fleet" do
      for _ <- 1..50 do
        fleet = Battleship.random_fleet()
        assert Battleship.fleet_complete?(fleet)
        assert length(fleet) == 5

        all_cells = Enum.flat_map(fleet, & &1.cells)
        assert length(all_cells) == length(Enum.uniq(all_cells))

        assert Enum.all?(all_cells, fn {col, row} -> col in 0..9 and row in 0..9 end)
      end
    end
  end

  describe "ready_up/2" do
    setup do
      {:ok, battleship: %Battleship{player_fleet: Battleship.random_fleet(), opponent_fleet: Battleship.random_fleet()}}
    end

    test "rejects an incomplete fleet", %{battleship: battleship} do
      battleship = %{battleship | player_fleet: []}
      assert Battleship.ready_up(battleship, :player) == {:error, :fleet_incomplete}
    end

    test "marks a side ready without starting the match alone", %{battleship: battleship} do
      {:ok, battleship} = Battleship.ready_up(battleship, :player)
      assert battleship.player_ready?
      refute battleship.opponent_ready?
      assert battleship.status == :placing_fleets
    end

    test "starts the match once both sides are ready", %{battleship: battleship} do
      {:ok, battleship} = Battleship.ready_up(battleship, :player)
      {:ok, battleship} = Battleship.ready_up(battleship, :opponent)
      assert battleship.status in [:player_turn, :opponent_turn]
    end

    test "the first turn is randomized across many matches" do
      statuses =
        for _ <- 1..40 do
          battleship = %Battleship{
            player_fleet: Battleship.random_fleet(),
            opponent_fleet: Battleship.random_fleet()
          }

          {:ok, battleship} = Battleship.ready_up(battleship, :player)
          {:ok, battleship} = Battleship.ready_up(battleship, :opponent)
          battleship.status
        end
        |> Enum.uniq()
        |> Enum.sort()

      assert statuses == [:opponent_turn, :player_turn]
    end
  end

  describe "fire/3" do
    setup do
      {:ok, opponent_fleet} = Battleship.place_ship([], :destroyer, {0, 0}, :horizontal)

      battleship = %Battleship{
        player_fleet: Battleship.random_fleet(),
        opponent_fleet: opponent_fleet,
        player_ready?: true,
        opponent_ready?: true,
        status: :player_turn
      }

      {:ok, battleship: battleship}
    end

    test "rejects firing out of turn", %{battleship: battleship} do
      assert Battleship.fire(battleship, :opponent, {5, 5}) == {:error, :not_your_turn}
    end

    test "rejects a side firing at a cell it has already shot", %{battleship: battleship} do
      {:ok, _result, battleship} = Battleship.fire(battleship, :player, {5, 5})
      {:ok, _result, battleship} = Battleship.fire(battleship, :opponent, {6, 6})
      assert Battleship.fire(battleship, :player, {5, 5}) == {:error, :already_shot}
    end

    test "a miss records the shot and flips turn", %{battleship: battleship} do
      {:ok, %{result: :miss, ship_type: nil}, battleship} = Battleship.fire(battleship, :player, {5, 5})
      assert battleship.player_shots["F6"] == "miss"
      assert battleship.status == :opponent_turn
    end

    test "a hit records the shot, flips turn, and does not sink the ship yet", %{battleship: battleship} do
      {:ok, %{result: :hit, ship_type: :destroyer}, battleship} = Battleship.fire(battleship, :player, {0, 0})
      assert battleship.player_shots["A1"] == "hit"
      assert battleship.status == :opponent_turn
    end

    test "sinking the last cell of a ship reports :sunk and wins the game", %{battleship: battleship} do
      {:ok, %{result: :hit}, battleship} = Battleship.fire(battleship, :player, {0, 0})
      {:ok, _result, battleship} = Battleship.fire(battleship, :opponent, {5, 5})
      {:ok, %{result: :sunk, ship_type: :destroyer}, battleship} = Battleship.fire(battleship, :player, {1, 0})
      assert battleship.status == :player_won
    end

    test "rejects any further shots once the game is over", %{battleship: battleship} do
      {:ok, _result, battleship} = Battleship.fire(battleship, :player, {0, 0})
      {:ok, _result, battleship} = Battleship.fire(battleship, :opponent, {5, 5})
      {:ok, _result, battleship} = Battleship.fire(battleship, :player, {1, 0})
      assert battleship.status == :player_won
      assert Battleship.fire(battleship, :opponent, {6, 6}) == {:error, :game_over}
    end
  end
end
