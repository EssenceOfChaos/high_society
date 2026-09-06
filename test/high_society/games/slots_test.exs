defmodule HighSociety.Games.SlotsTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.Slots

  # Builds a 24-cell grid (column-major, index = col*4+row) from a map of
  # {col, row} => kind overrides, filling every other cell with `filler`
  # (:bonus by default - it breaks any payline it touches immediately, so
  # it never contaminates an assertion about one specific payline).
  defp grid(overrides, filler \\ :bonus) do
    # col outer, row inner - matches Slots' column-major `col*4+row` storage
    # order exactly (each col's 4 rows land consecutively).
    for col <- 0..5, row <- 0..3, do: Map.get(overrides, {col, row}, filler)
  end

  describe "wager_options/0" do
    test "is the 12 fixed cent amounts from $0.25 to $10.00" do
      assert Slots.wager_options() == [25, 50, 75, 100, 125, 150, 175, 200, 250, 300, 500, 1000]
    end
  end

  describe "paylines/0" do
    test "is 16 paylines, each 6 row indices in 0..3" do
      paylines = Slots.paylines()
      assert length(paylines) == 16

      for payline <- paylines do
        assert length(payline) == 6
        assert Enum.all?(payline, &(&1 in 0..3))
      end
    end
  end

  describe "reel_weights/0" do
    test "sums to 200 across all 10 symbols" do
      weights = Slots.reel_weights()
      assert length(weights) == 10
      assert weights |> Keyword.values() |> Enum.sum() == 200
    end
  end

  describe "evaluate/2 - payline scoring" do
    test "a plain run of one symbol pays that symbol's row" do
      # payline 0 is the top row: col*4+0 for col in 0..5
      overrides = for col <- 0..5, into: %{}, do: {{col, 0}, :cherries}
      result = Slots.evaluate(grid(overrides))

      assert %{payline: 0, kind: :cherries, length: 6, multiplier_hundredths: 800} in result.wins
    end

    test "Wild substitutes for the first real symbol in the run, extending its length" do
      overrides = %{
        {0, 0} => :wild,
        {1, 0} => :wild,
        {2, 0} => :cherries,
        {3, 0} => :cherries,
        {4, 0} => :lemon,
        {5, 0} => :grapes
      }

      result = Slots.evaluate(grid(overrides))

      assert %{payline: 0, kind: :cherries, length: 4, multiplier_hundredths: 75} in result.wins
    end

    test "an all-Wild run pays Wild's own (higher) row" do
      overrides = for col <- 0..5, into: %{}, do: {{col, 1}, :wild}
      result = Slots.evaluate(grid(overrides))

      # payline 1 is the second row: col*4+1
      assert %{payline: 1, kind: :wild, length: 6, multiplier_hundredths: 30_000} in result.wins
    end

    test "a Bonus symbol breaks the run instead of paying or substituting" do
      overrides = %{
        {0, 2} => :cherries,
        {1, 2} => :cherries,
        {2, 2} => :bonus,
        {3, 2} => :cherries,
        {4, 2} => :cherries,
        {5, 2} => :cherries
      }

      result = Slots.evaluate(grid(overrides))

      # payline 2 is the third row: col*4+2 - only 2 cherries before the
      # break, below the 3-of-a-kind minimum, so no win is reported for it
      refute Enum.any?(result.wins, &(&1.payline == 2))
    end

    test "a run under 3 long never pays" do
      overrides = %{{0, 3} => :seven, {1, 3} => :seven, {2, 3} => :lemon}
      result = Slots.evaluate(grid(overrides))

      refute Enum.any?(result.wins, &(&1.payline == 3))
    end

    test "feature_multiplier scales every win's payout" do
      overrides = for col <- 0..5, into: %{}, do: {{col, 0}, :lemon}
      result = Slots.evaluate(grid(overrides), 3)

      assert %{payline: 0, kind: :lemon, length: 6, multiplier_hundredths: 3000} in result.wins
    end

    test "bonus_count tallies every Bonus symbol on the grid" do
      overrides = %{{0, 0} => :bonus, {3, 2} => :bonus, {5, 3} => :bonus}
      result = Slots.evaluate(grid(overrides, :cherries))

      assert result.bonus_count == 3
    end
  end

  describe "apply_bonus/4" do
    test "fewer than the trigger count changes nothing" do
      assert Slots.apply_bonus(0, false, 1, Slots.bonus_trigger_count() - 1) == {0, 1, false}
    end

    test "a fresh trigger awards free spins and sets the feature multiplier" do
      assert Slots.apply_bonus(0, false, 1, Slots.bonus_trigger_count()) ==
               {Slots.free_spins_award(), Slots.free_spin_multiplier(), true}
    end

    test "a retrigger during free spins adds spins but keeps the multiplier" do
      assert Slots.apply_bonus(5, true, 3, Slots.bonus_trigger_count()) ==
               {5 + Slots.free_spins_retrigger_award(), 3, true}
    end
  end

  describe "RTP guard rail" do
    test "long-run simulated return sits in a broad, sane band" do
      wager = 100
      spins = 50_000

      {wagered, paid, _remaining, _multiplier} =
        Enum.reduce(1..spins, {0, 0, 0, 1}, fn _, {wagered, paid, remaining, multiplier} ->
          free? = remaining > 0
          feature_multiplier = if free?, do: multiplier, else: 1
          result = Slots.spin(feature_multiplier)

          remaining_after = if free?, do: remaining - 1, else: 0

          {new_remaining, new_multiplier, _triggered?} =
            Slots.apply_bonus(remaining_after, free?, feature_multiplier, result.bonus_count)

          win = div(wager * result.total_multiplier_hundredths, 100)
          wagered_this = if free?, do: 0, else: wager

          {wagered + wagered_this, paid + win, new_remaining, new_multiplier}
        end)

      rtp = paid / wagered

      assert rtp > 0.85 and rtp < 1.05,
             "measured RTP #{Float.round(rtp * 100, 2)}% is outside the sane 85-105% band - re-tune the paytable/weights"
    end
  end
end
