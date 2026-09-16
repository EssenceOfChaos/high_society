defmodule HighSociety.Games.ZombieAttackTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.ZombieAttack

  describe "wave_schedule/1" do
    test "returns more zombies as the wave number increases" do
      counts =
        for wave <- 1..ZombieAttack.wave_count(), do: length(ZombieAttack.wave_schedule(wave))

      assert counts == Enum.sort(counts)
    end

    test "every spawn is on a valid lane, with a valid zombie type and a non-negative spawn time" do
      for wave <- 1..ZombieAttack.wave_count(), spawn <- ZombieAttack.wave_schedule(wave) do
        assert spawn.lane in 0..(ZombieAttack.lanes() - 1)
        assert spawn.zombie_type in Map.keys(ZombieAttack.zombie_specs())
        assert spawn.spawn_at_ms >= 0
      end
    end

    test "later waves have a strictly later last spawn than wave 1" do
      wave_1_end = ZombieAttack.wave_schedule(1) |> List.last() |> Map.fetch!(:spawn_at_ms)

      last_wave_end =
        ZombieAttack.wave_schedule(ZombieAttack.wave_count())
        |> List.last()
        |> Map.fetch!(:spawn_at_ms)

      assert last_wave_end > wave_1_end
    end
  end

  describe "full_wave_schedule/0" do
    test "returns one entry per wave, each wrapped with its wave number" do
      schedule = ZombieAttack.full_wave_schedule()
      assert length(schedule) == ZombieAttack.wave_count()
      assert Enum.map(schedule, & &1.wave) == Enum.to_list(1..ZombieAttack.wave_count())
    end
  end

  describe "payout_for/2" do
    test "losing during wave 1 pays nothing" do
      assert ZombieAttack.payout_for(1000, {:cleared_wave, 0}) == 0
    end

    test "clearing wave 3 breaks even" do
      assert ZombieAttack.payout_for(1000, {:cleared_wave, 3}) == 1000
    end

    test "a full clear pays out more than clearing any partial wave" do
      partial = ZombieAttack.payout_for(1000, {:cleared_wave, ZombieAttack.wave_count()})
      full = ZombieAttack.payout_for(1000, :full_clear)
      assert full == partial
      assert full > ZombieAttack.payout_for(1000, {:cleared_wave, ZombieAttack.wave_count() - 1})
    end
  end

  describe "valid_next_wave?/2" do
    test "accepts exactly the next wave" do
      assert ZombieAttack.valid_next_wave?(0, 1)
      assert ZombieAttack.valid_next_wave?(2, 3)
    end

    test "rejects skipping ahead" do
      refute ZombieAttack.valid_next_wave?(0, 2)
    end

    test "rejects repeating or going backward" do
      refute ZombieAttack.valid_next_wave?(2, 2)
      refute ZombieAttack.valid_next_wave?(2, 1)
    end
  end
end
