defmodule HighSociety.BadgesTest do
  use ExUnit.Case, async: true

  alias HighSociety.Badges

  describe "for_active_days/1" do
    test "starts every player at Novice" do
      assert Badges.for_active_days(0).slug == "novice"
      assert Badges.for_active_days(1).slug == "novice"
    end

    test "climbs the Fibonacci thresholds as active days grow" do
      assert Badges.for_active_days(2).slug == "apprentice"
      assert Badges.for_active_days(3).slug == "player"
      assert Badges.for_active_days(5).slug == "skilled"
      assert Badges.for_active_days(8).slug == "expert"
      assert Badges.for_active_days(13).slug == "master"
      assert Badges.for_active_days(21).slug == "grandmaster"
      assert Badges.for_active_days(34).slug == "champion"
      assert Badges.for_active_days(55).slug == "legend"
      assert Badges.for_active_days(89).slug == "high-society"
    end

    test "stays on the previous badge until its threshold is reached" do
      assert Badges.for_active_days(4).slug == "player"
      assert Badges.for_active_days(20).slug == "master"
    end

    test "caps at the top badge beyond its threshold" do
      assert Badges.for_active_days(1_000).slug == "high-society"
    end
  end

  describe "all/0" do
    test "is ordered from lowest to highest threshold" do
      thresholds = Badges.all() |> Enum.map(& &1.threshold)
      assert thresholds == Enum.sort(thresholds)
    end
  end
end
