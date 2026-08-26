defmodule HighSociety.Games.BlackjackTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.Blackjack

  describe "new/1" do
    test "deals two cards to each requested box and two to the dealer" do
      game = Blackjack.new(%{0 => 25, 1 => 50})

      assert length(game.hands) == 2
      assert Enum.map(game.hands, & &1.box) == [0, 1]
      assert Enum.map(game.hands, & &1.bet) == [25, 50]
      assert Enum.all?(game.hands, &(length(&1.cards) == 2))
      assert length(game.dealer_hand) == 2
      assert game.status in [:player_turn, :round_over]

      all_cards = Enum.flat_map(game.hands, & &1.cards) ++ game.dealer_hand ++ game.shoe
      assert length(Enum.uniq(all_cards)) == 52
    end

    test "a single box deals only one hand" do
      game = Blackjack.new(%{0 => 100})

      assert length(game.hands) == 1
      assert hd(game.hands).box == 0
    end

    test "starts play on whichever dealt box still needs a decision" do
      game = Blackjack.new(%{0 => 25, 1 => 25})

      if game.status == :player_turn do
        first_active = Enum.find(game.hands, &(&1.status == :active))
        assert game.active_hand == first_active.box
      else
        # both boxes happened to be dealt a natural blackjack - nothing to play
        assert Enum.all?(game.hands, &(&1.status == :blackjack))
        assert game.active_hand == nil
      end
    end
  end

  describe "hit/2" do
    test "draws a card into the active hand and stays active if under 21" do
      game = %Blackjack{
        shoe: ["2S", "9S"],
        hands: [
          %{box: 0, bet: 25, cards: ["5H", "5D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["7H", "7D"],
        status: :player_turn
      }

      game = Blackjack.hit(game, 0)
      hand = hd(game.hands)

      assert hand.cards == ["5H", "5D", "2S"]
      assert hand.status == :active
      assert game.status == :player_turn
      assert game.active_hand == 0
      assert game.shoe == ["9S"]
    end

    test "busts over 21 and advances to the dealer when it was the only hand" do
      game = %Blackjack{
        shoe: ["KS"],
        hands: [
          %{box: 0, bet: 25, cards: ["10H", "5D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10H", "7D"],
        status: :player_turn
      }

      game = Blackjack.hit(game, 0)
      hand = hd(game.hands)

      assert hand.status == :busted
      assert hand.outcome == :loss
      assert hand.payout == 0
      assert game.status == :round_over
      assert game.active_hand == nil
    end

    test "hitting to exactly 21 auto-stands" do
      game = %Blackjack{
        shoe: ["AS"],
        hands: [
          %{box: 0, bet: 25, cards: ["10H", "10D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10H", "7D"],
        status: :player_turn
      }

      game = Blackjack.hit(game, 0)
      hand = hd(game.hands)

      assert Blackjack.value(hand.cards) == 21
      assert hand.status == :standing
    end

    test "finishing box 0 advances the active hand to box 1" do
      game = %Blackjack{
        shoe: ["KS", "2H"],
        hands: [
          %{box: 0, bet: 25, cards: ["10H", "5D"], status: :active, outcome: nil, payout: nil},
          %{box: 1, bet: 25, cards: ["6H", "6D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["7H", "6C"],
        status: :player_turn
      }

      # bust box 0 -> should move to box 1, not the dealer, since box 1 is still active
      game = Blackjack.hit(game, 0)

      assert game.status == :player_turn
      assert game.active_hand == 1
      box0 = Enum.find(game.hands, &(&1.box == 0))
      assert box0.status == :busted
    end
  end

  describe "stand/2 and dealer play" do
    test "dealer stands on a soft 17 rather than hitting" do
      game = %Blackjack{
        shoe: ["6H"],
        hands: [
          %{box: 0, bet: 25, cards: ["10H", "8D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        # dealer starts on a soft 17 (A + 6) and must stand, not hit
        dealer_hand: ["AS", "6D"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0)

      assert game.dealer_hand == ["AS", "6D"]
      assert game.status == :round_over
    end

    test "dealer hits until reaching at least 17" do
      game = %Blackjack{
        shoe: ["5S", "9S"],
        hands: [
          %{box: 0, bet: 25, cards: ["10H", "8D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["2S", "3S"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0)

      assert game.dealer_hand == ["2S", "3S", "5S", "9S"]
      assert Blackjack.value(game.dealer_hand) == 19
      assert game.status == :round_over
      assert game.shoe == []
    end
  end

  describe "settlement payouts" do
    test "a standing hand beats a dealer bust and pays 1:1" do
      game = %Blackjack{
        shoe: ["KS"],
        hands: [
          %{box: 0, bet: 25, cards: ["10H", "8D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10S", "6C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0)
      hand = hd(game.hands)

      assert Blackjack.busted?(game.dealer_hand)
      assert hand.outcome == :win
      assert hand.payout == 50
    end

    test "a higher standing total than the dealer's wins 1:1" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{box: 0, bet: 25, cards: ["10H", "9D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10S", "8C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0)
      hand = hd(game.hands)

      assert hand.outcome == :win
      assert hand.payout == 50
    end

    test "equal totals push and return the bet" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{box: 0, bet: 25, cards: ["10H", "9D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10S", "9C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0)
      hand = hd(game.hands)

      assert hand.outcome == :push
      assert hand.payout == 25
    end

    test "a lower standing total than the dealer's loses" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{box: 0, bet: 25, cards: ["10H", "7D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10S", "9C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0)
      hand = hd(game.hands)

      assert hand.outcome == :loss
      assert hand.payout == 0
    end

    test "a natural blackjack pays 3:2 against a non-blackjack dealer" do
      # box 0 was already dealt a natural; box 1 is the active hand whose
      # stand triggers settlement of both, exactly as new/1 would if only
      # one of the two boxes came up a natural on the deal
      game = %Blackjack{
        shoe: [],
        hands: [
          %{box: 0, bet: 100, cards: ["AS", "KH"], status: :blackjack, outcome: nil, payout: nil},
          %{box: 1, bet: 25, cards: ["9S", "5H"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 1,
        dealer_hand: ["10S", "7C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 1)
      hand = Enum.find(game.hands, &(&1.box == 0))

      assert hand.outcome == :blackjack_win
      # 100 bet returned + 150 winnings = 250 total
      assert hand.payout == 250
    end

    test "a natural blackjack pays 3:2 with floor rounding on an odd bet" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{box: 0, bet: 25, cards: ["AS", "KH"], status: :blackjack, outcome: nil, payout: nil},
          %{box: 1, bet: 25, cards: ["9S", "5H"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 1,
        dealer_hand: ["10S", "7C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 1)
      hand = Enum.find(game.hands, &(&1.box == 0))

      assert hand.outcome == :blackjack_win
      # bet 25 + floor(25 * 3 / 2) = 25 + 37 = 62, not 62.5/63
      assert hand.payout == 62
    end

    test "a natural blackjack pushes against a dealer natural blackjack" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{box: 0, bet: 100, cards: ["AS", "KH"], status: :blackjack, outcome: nil, payout: nil},
          %{box: 1, bet: 25, cards: ["9S", "5H"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 1,
        dealer_hand: ["AH", "KD"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 1)
      hand = Enum.find(game.hands, &(&1.box == 0))

      assert Blackjack.blackjack?(game.dealer_hand)
      assert hand.outcome == :push
      assert hand.payout == 100
    end

    test "a non-natural 21 loses to a dealer's natural blackjack" do
      game = %Blackjack{
        shoe: ["7C"],
        hands: [
          %{
            box: 0,
            bet: 25,
            cards: ["7H", "3D", "AC"],
            status: :active,
            outcome: nil,
            payout: nil
          }
        ],
        active_hand: 0,
        dealer_hand: ["AS", "KH"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0)
      hand = hd(game.hands)

      assert Blackjack.value(hand.cards) == 21
      assert Blackjack.blackjack?(game.dealer_hand)
      assert hand.outcome == :loss
      assert hand.payout == 0
    end
  end

  describe "value/1" do
    test "counts face cards as 10 and aces as 11 unless that would bust" do
      assert Blackjack.value(["KH", "QS"]) == 20
      assert Blackjack.value(["AS", "KH"]) == 21
      assert Blackjack.value(["AS", "9H", "5D"]) == 15
      assert Blackjack.value(["AS", "AH"]) == 12
    end
  end

  test "conserves all cards with no duplicates across many full rounds" do
    for _ <- 1..50 do
      bets = Enum.random([%{0 => 25}, %{0 => 25, 1 => 50}])
      game = Blackjack.new(bets)

      game =
        Stream.iterate(game, fn game ->
          if game.status == :player_turn do
            if Enum.random([true, false]),
              do: Blackjack.hit(game, game.active_hand),
              else: Blackjack.stand(game, game.active_hand)
          else
            game
          end
        end)
        |> Enum.find(&(&1.status == :round_over))

      all_cards = Enum.flat_map(game.hands, & &1.cards) ++ game.dealer_hand ++ game.shoe
      assert length(all_cards) == length(Enum.uniq(all_cards))
      assert length(all_cards) <= 52
      assert Enum.all?(game.hands, &(&1.outcome != nil and &1.payout != nil))
    end
  end
end
