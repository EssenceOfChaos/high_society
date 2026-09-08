defmodule HighSociety.Games.RouletteTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.Roulette

  describe "wheel_order/0" do
    test "is all 37 pockets (0-36), each exactly once" do
      order = Roulette.wheel_order()
      assert length(order) == 37
      assert Enum.sort(order) == Enum.to_list(0..36)
    end
  end

  describe "color/1" do
    test "0 is green" do
      assert Roulette.color(0) == :green
    end

    test "every non-zero number is red or black, split 18/18" do
      colors = for n <- 1..36, do: Roulette.color(n)
      assert Enum.all?(colors, &(&1 in [:red, :black]))
      assert Enum.count(colors, &(&1 == :red)) == 18
      assert Enum.count(colors, &(&1 == :black)) == 18
    end

    test "a few known reference numbers match a real wheel" do
      assert Roulette.color(1) == :red
      assert Roulette.color(2) == :black
      assert Roulette.color(17) == :black
      assert Roulette.color(36) == :red
    end
  end

  describe "spin/0" do
    test "always draws a number in 0..36" do
      for _ <- 1..500 do
        assert Roulette.spin() in 0..36
      end
    end
  end

  describe "valid_key?/1" do
    test "accepts every straight number 0-36" do
      for n <- 0..36, do: assert(Roulette.valid_key?("straight:#{n}"))
    end

    test "rejects an out-of-range straight number" do
      refute Roulette.valid_key?("straight:37")
      refute Roulette.valid_key?("straight:-1")
    end

    test "accepts the fixed outside bets, dozens, and columns" do
      for key <-
            ~w(red black odd even low high dozen:1 dozen:2 dozen:3 column:1 column:2 column:3) do
        assert Roulette.valid_key?(key)
      end
    end

    test "rejects garbage" do
      refute Roulette.valid_key?("dozen:4")
      refute Roulette.valid_key?("column:0")
      refute Roulette.valid_key?("purple")
      refute Roulette.valid_key?("straight:")
    end
  end

  describe "evaluate/2 - straight bets" do
    test "a winning straight bet pays 36x (35:1 plus the stake back)" do
      [result] = Roulette.evaluate(17, %{"straight:17" => 100})
      assert result == %{key: "straight:17", amount: 100, payout: 3600, won?: true}
    end

    test "a losing straight bet pays nothing" do
      [result] = Roulette.evaluate(18, %{"straight:17" => 100})
      assert result.won? == false
      assert result.payout == 0
    end
  end

  describe "evaluate/2 - color/parity/range bets" do
    test "red pays 2x on a red number, nothing on black or green" do
      assert [%{won?: true, payout: 200}] = Roulette.evaluate(1, %{"red" => 100})
      assert [%{won?: false, payout: 0}] = Roulette.evaluate(2, %{"red" => 100})
      assert [%{won?: false, payout: 0}] = Roulette.evaluate(0, %{"red" => 100})
    end

    test "black pays 2x on a black number" do
      assert [%{won?: true, payout: 200}] = Roulette.evaluate(2, %{"black" => 100})
    end

    test "odd/even ignore zero entirely" do
      assert [%{won?: true}] = Roulette.evaluate(3, %{"odd" => 100})
      assert [%{won?: false}] = Roulette.evaluate(0, %{"odd" => 100})
      assert [%{won?: true}] = Roulette.evaluate(4, %{"even" => 100})
      assert [%{won?: false}] = Roulette.evaluate(0, %{"even" => 100})
    end

    test "low covers 1-18, high covers 19-36, neither covers zero" do
      assert [%{won?: true}] = Roulette.evaluate(18, %{"low" => 100})
      assert [%{won?: false}] = Roulette.evaluate(19, %{"low" => 100})
      assert [%{won?: true}] = Roulette.evaluate(19, %{"high" => 100})
      assert [%{won?: false}] = Roulette.evaluate(0, %{"high" => 100})
    end
  end

  describe "evaluate/2 - dozens and columns" do
    test "dozens split 1-12/13-24/25-36 and pay 3x, excluding zero" do
      assert [%{won?: true, payout: 300}] = Roulette.evaluate(12, %{"dozen:1" => 100})
      assert [%{won?: false}] = Roulette.evaluate(13, %{"dozen:1" => 100})
      assert [%{won?: true}] = Roulette.evaluate(13, %{"dozen:2" => 100})
      assert [%{won?: true}] = Roulette.evaluate(36, %{"dozen:3" => 100})
      assert [%{won?: false}] = Roulette.evaluate(0, %{"dozen:1" => 100})
    end

    test "columns follow the table's left-to-right number layout and pay 3x" do
      # column 1 is 1,4,7,...,34; column 2 is 2,5,8,...,35; column 3 is 3,6,...,36
      assert [%{won?: true, payout: 300}] = Roulette.evaluate(1, %{"column:1" => 100})
      assert [%{won?: true}] = Roulette.evaluate(34, %{"column:1" => 100})
      assert [%{won?: true}] = Roulette.evaluate(2, %{"column:2" => 100})
      assert [%{won?: true}] = Roulette.evaluate(36, %{"column:3" => 100})
      assert [%{won?: false}] = Roulette.evaluate(1, %{"column:2" => 100})
      assert [%{won?: false}] = Roulette.evaluate(0, %{"column:1" => 100})
    end
  end

  describe "evaluate/2 - multiple simultaneous bets" do
    test "settles every bet independently and preserves each one's own key" do
      results = Roulette.evaluate(7, %{"straight:7" => 50, "red" => 100, "black" => 25})
      by_key = Map.new(results, &{&1.key, &1})

      assert by_key["straight:7"].won? == true
      assert by_key["straight:7"].payout == 1800
      assert by_key["red"].won? == true
      assert by_key["red"].payout == 200
      assert by_key["black"].won? == false
      assert by_key["black"].payout == 0
    end
  end

  describe "RTP guard rail" do
    test "long-run simulated return sits in a sane band for an even-money bet" do
      spins = 20_000
      wager = 100

      paid =
        1..spins
        |> Enum.map(fn _ -> Roulette.evaluate(Roulette.spin(), %{"red" => wager}) end)
        |> List.flatten()
        |> Enum.map(& &1.payout)
        |> Enum.sum()

      rtp = paid / (spins * wager)

      assert rtp > 0.90 and rtp < 1.05,
             "measured RTP #{Float.round(rtp * 100, 2)}% is outside the sane band for a single-zero even-money bet (true house edge is 2.7%)"
    end
  end
end
