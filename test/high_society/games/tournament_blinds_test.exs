defmodule HighSociety.Games.TournamentBlindsTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.TournamentBlinds

  describe "default_schedule/0" do
    test "has 15 levels, big blind always double the small blind" do
      schedule = TournamentBlinds.default_schedule()
      assert length(schedule) == 15

      for %{small_blind: sb, big_blind: bb} <- schedule do
        assert bb == sb * 2
      end
    end

    test "starts at 100/200 and ends at 15000/30000" do
      schedule = TournamentBlinds.default_schedule()
      assert List.first(schedule) == %{small_blind: 100, big_blind: 200}
      assert List.last(schedule) == %{small_blind: 15_000, big_blind: 30_000}
    end

    test "no level-to-level jump exceeds 1.8x, in either direction" do
      schedule = TournamentBlinds.default_schedule()

      schedule
      |> Enum.zip(tl(schedule))
      |> Enum.each(fn {prev, next} ->
        ratio = next.big_blind / prev.big_blind
        assert ratio <= 1.8, "jump from #{inspect(prev)} to #{inspect(next)} was #{ratio}x"
        assert ratio >= 1.0
      end)
    end
  end

  test "level_count/0 matches default_schedule/0" do
    assert TournamentBlinds.level_count() == length(TournamentBlinds.default_schedule())
  end
end
