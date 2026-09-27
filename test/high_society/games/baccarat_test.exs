defmodule HighSociety.Games.BaccaratTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.Baccarat

  describe "point_value/1" do
    test "Ace is 1, 2-9 are face value, 10/J/Q/K are 0, regardless of suit" do
      assert Baccarat.point_value("AS") == 1
      assert Baccarat.point_value("AH") == 1
      assert Baccarat.point_value("2D") == 2
      assert Baccarat.point_value("9C") == 9
      assert Baccarat.point_value("10S") == 0
      assert Baccarat.point_value("JH") == 0
      assert Baccarat.point_value("QD") == 0
      assert Baccarat.point_value("KC") == 0
    end
  end

  describe "hand_total/1" do
    test "sums point values mod 10" do
      assert Baccarat.hand_total(["9S", "9H"]) == 8
      assert Baccarat.hand_total(["KS", "QH"]) == 0
      assert Baccarat.hand_total(["AS", "2H"]) == 3
      assert Baccarat.hand_total(["5S", "5H", "5D"]) == 5
    end
  end

  describe "split_card/1" do
    test "splits rank and suit, including two-character ranks" do
      assert Baccarat.split_card("AS") == {"A", "S"}
      assert Baccarat.split_card("10H") == {"10", "H"}
      assert Baccarat.split_card("KC") == {"K", "C"}
    end
  end

  describe "valid_key?/1 and max_bet/0" do
    test "player, banker, and tie are valid; anything else isn't" do
      assert Baccarat.valid_key?("player")
      assert Baccarat.valid_key?("banker")
      assert Baccarat.valid_key?("tie")
      refute Baccarat.valid_key?("pair")
      refute Baccarat.valid_key?("")
    end

    test "max_bet is a positive integer" do
      assert Baccarat.max_bet() > 0
    end
  end

  describe "banker_draws_after_player_third?/2 - the official drawing table" do
    test "Banker total 0-2 always draws, regardless of Player's third card" do
      for banker_total <- 0..2, player_third <- 0..9 do
        assert Baccarat.banker_draws_after_player_third?(banker_total, player_third)
      end
    end

    test "Banker total 3 draws unless Player's third card is 8" do
      for player_third <- 0..9, player_third != 8 do
        assert Baccarat.banker_draws_after_player_third?(3, player_third)
      end

      refute Baccarat.banker_draws_after_player_third?(3, 8)
    end

    test "Banker total 4 draws only if Player's third card is 2-7" do
      for player_third <- 2..7 do
        assert Baccarat.banker_draws_after_player_third?(4, player_third)
      end

      for player_third <- [0, 1, 8, 9] do
        refute Baccarat.banker_draws_after_player_third?(4, player_third)
      end
    end

    test "Banker total 5 draws only if Player's third card is 4-7" do
      for player_third <- 4..7 do
        assert Baccarat.banker_draws_after_player_third?(5, player_third)
      end

      for player_third <- [0, 1, 2, 3, 8, 9] do
        refute Baccarat.banker_draws_after_player_third?(5, player_third)
      end
    end

    test "Banker total 6 draws only if Player's third card is 6-7" do
      for player_third <- 6..7 do
        assert Baccarat.banker_draws_after_player_third?(6, player_third)
      end

      for player_third <- [0, 1, 2, 3, 4, 5, 8, 9] do
        refute Baccarat.banker_draws_after_player_third?(6, player_third)
      end
    end

    test "Banker total 7 never draws" do
      for player_third <- 0..9 do
        refute Baccarat.banker_draws_after_player_third?(7, player_third)
      end
    end
  end

  describe "resolve/4 - natural hands" do
    test "a natural Player 8 ends the hand immediately, even if Banker's total would normally draw" do
      # Banker's 2-card total is 4, which would draw a third card under the
      # normal rule - but Player's natural 8 must stop everything.
      game = Baccarat.resolve(["3S", "5H"], ["2S", "2H"], ["9S", "9H"], %{})

      assert game.player_hand == ["3S", "5H"]
      assert game.banker_hand == ["2S", "2H"]
      assert game.player_total == 8
      assert game.banker_total == 4
      assert game.outcome == :player
    end

    test "a natural Banker 9 ends the hand immediately, even if Player's total would normally draw" do
      # Player's 2-card total is 5, which would normally draw a third card.
      game = Baccarat.resolve(["2S", "3H"], ["4S", "5H"], ["9S", "9H"], %{})

      assert game.player_hand == ["2S", "3H"]
      assert game.banker_hand == ["4S", "5H"]
      assert game.player_total == 5
      assert game.banker_total == 9
      assert game.outcome == :banker
    end
  end

  describe "resolve/4 - Player stands (6 or 7)" do
    test "Banker draws on a total of 0-5 when Player stood", %{} do
      game = Baccarat.resolve(["3S", "3H"], ["2S", "2H"], ["5H"], %{})

      # Player total 6 stands; Banker total 4 draws using the same 0-5 rule
      # Player would have used, independent of any Player third card.
      assert game.player_total == 6
      assert game.player_hand == ["3S", "3H"]
      assert game.banker_hand == ["2S", "2H", "5H"]
    end

    test "Banker stands on a total of 6-7 when Player stood" do
      game = Baccarat.resolve(["3S", "3H"], ["3S", "3H"], ["5H"], %{})

      assert game.player_total == 6
      assert game.banker_hand == ["3S", "3H"]
      assert game.outcome == :tie
    end
  end

  describe "resolve/4 - Player draws a third card" do
    test "Banker with total 3 stands when Player's third card is 8" do
      game = Baccarat.resolve(["2S", "3H"], ["AS", "2H"], ["8H", "9C"], %{})

      assert game.player_hand == ["2S", "3H", "8H"]
      assert game.banker_hand == ["AS", "2H"]
      assert game.player_total == 3
      assert game.banker_total == 3
      assert game.outcome == :tie
    end

    test "Banker with total 3 draws when Player's third card isn't 8" do
      game = Baccarat.resolve(["2S", "3H"], ["AS", "2H"], ["5H", "9C"], %{})

      assert game.player_hand == ["2S", "3H", "5H"]
      assert game.banker_hand == ["AS", "2H", "9C"]
    end
  end

  describe "resolve/4 - settlement" do
    test "a Player win pays Player bets 1:1 (stake included) and loses Banker/Tie bets" do
      bets = %{"player" => 1_000, "banker" => 500, "tie" => 100}
      game = Baccarat.resolve(["9S", "9H"], ["2S", "2H"], [], bets)

      assert game.outcome == :player

      assert %{key: "player", amount: 1_000, payout: 2_000, won?: true} in game.bets
      assert %{key: "banker", amount: 500, payout: 0, won?: false} in game.bets
      assert %{key: "tie", amount: 100, payout: 0, won?: false} in game.bets
    end

    test "a Banker win pays Banker bets 0.95:1 (5% commission, integer division) and loses the rest" do
      bets = %{"player" => 1_000, "banker" => 1_000, "tie" => 100}
      game = Baccarat.resolve(["2S", "2H"], ["9S", "9H"], [], bets)

      assert game.outcome == :banker
      # 1_000 stake + 950 profit (5% commission off 1_000 via div/2 - no floats)
      assert %{key: "banker", amount: 1_000, payout: 1_950, won?: true} in game.bets
      assert %{key: "player", amount: 1_000, payout: 0, won?: false} in game.bets
      assert %{key: "tie", amount: 100, payout: 0, won?: false} in game.bets
    end

    test "a Tie result pushes Player/Banker bets (stake returned, not a win) and pays Tie 8:1" do
      bets = %{"player" => 1_000, "banker" => 1_000, "tie" => 100}
      # Both hands stand on 6 (no draws needed) with an equal total.
      game = Baccarat.resolve(["4S", "2H"], ["4D", "2D"], [], bets)

      assert game.outcome == :tie
      assert %{key: "player", amount: 1_000, payout: 1_000, won?: false} in game.bets
      assert %{key: "banker", amount: 1_000, payout: 1_000, won?: false} in game.bets
      assert %{key: "tie", amount: 100, payout: 900, won?: true} in game.bets
    end
  end

  describe "deal/1" do
    test "always produces two valid 2-3 card hands drawn from a real 52-card deck, across many deals" do
      for _ <- 1..200 do
        game = Baccarat.deal(%{"player" => 100})

        assert length(game.player_hand) in [2, 3]
        assert length(game.banker_hand) in [2, 3]
        assert game.player_total in 0..9
        assert game.banker_total in 0..9
        assert game.outcome in [:player, :banker, :tie]

        all_cards = game.player_hand ++ game.banker_hand
        assert length(Enum.uniq(all_cards)) == length(all_cards)

        outcome =
          cond do
            game.player_total > game.banker_total -> :player
            game.banker_total > game.player_total -> :banker
            true -> :tie
          end

        assert game.outcome == outcome
      end
    end
  end
end
