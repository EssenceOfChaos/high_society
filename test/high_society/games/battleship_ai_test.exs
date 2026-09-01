defmodule HighSociety.Games.BattleshipAITest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.BattleshipAI

  describe "hunt mode (no live hits)" do
    test "only chooses cells on the checkerboard parity while any remain" do
      for _ <- 1..20 do
        {col, row} = BattleshipAI.choose_shot(%{}, [])
        assert rem(col + row, 2) == 0
      end
    end

    test "never re-chooses an already-shot cell" do
      shots_fired = for col <- 0..9, row <- 0..9, rem(col + row, 2) == 0, into: %{}, do: {{col, row}, :miss}
      {col, row} = BattleshipAI.choose_shot(shots_fired, [])
      assert rem(col + row, 2) == 1
      refute Map.has_key?(shots_fired, {col, row})
    end
  end

  describe "target mode (a single live hit)" do
    test "chooses an orthogonal, untried, on-board neighbor of the hit" do
      shots_fired = %{{5, 5} => :hit}

      for _ <- 1..20 do
        coord = BattleshipAI.choose_shot(shots_fired, [])
        assert coord in [{4, 5}, {6, 5}, {5, 4}, {5, 6}]
      end
    end

    test "falls back to hunting once every neighbor is off-board or already shot" do
      # {0, 0}'s only on-board neighbors are {1, 0} and {0, 1}, both already shot -
      # every candidate neighbor is excluded, so it must fall back to hunting.
      shots_fired = %{{0, 0} => :hit, {1, 0} => :miss, {0, 1} => :miss}
      coord = BattleshipAI.choose_shot(shots_fired, [])
      refute coord in [{1, 0}, {0, 1}]
      assert rem(elem(coord, 0) + elem(coord, 1), 2) == 0
    end
  end

  describe "target mode (two aligned live hits)" do
    test "extends a horizontal line past either known end" do
      shots_fired = %{{3, 4} => :hit, {5, 4} => :hit}

      for _ <- 1..20 do
        coord = BattleshipAI.choose_shot(shots_fired, [])
        assert coord in [{2, 4}, {4, 4}, {6, 4}]
      end
    end

    test "extends a vertical line past either known end" do
      shots_fired = %{{4, 3} => :hit, {4, 5} => :hit}

      for _ <- 1..20 do
        coord = BattleshipAI.choose_shot(shots_fired, [])
        assert coord in [{4, 2}, {4, 4}, {4, 6}]
      end
    end

    test "stops extending in a direction once it runs into a recorded miss" do
      shots_fired = %{{3, 4} => :hit, {4, 4} => :hit, {5, 4} => :miss}

      for _ <- 1..20 do
        assert BattleshipAI.choose_shot(shots_fired, []) == {2, 4}
      end
    end

    test "stops extending in a direction once it runs off the board" do
      shots_fired = %{{0, 4} => :hit, {1, 4} => :hit}

      for _ <- 1..20 do
        assert BattleshipAI.choose_shot(shots_fired, []) == {2, 4}
      end
    end
  end

  describe "resuming hunt mode after a ship sinks" do
    test "a live hit whose ship is fully sunk no longer counts as a pending target" do
      shots_fired = %{{5, 5} => :hit}

      coord = BattleshipAI.choose_shot(shots_fired, [{5, 5}])
      assert rem(elem(coord, 0) + elem(coord, 1), 2) == 0
    end
  end
end
