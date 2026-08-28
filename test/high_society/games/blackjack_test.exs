defmodule HighSociety.Games.BlackjackTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.Blackjack

  # Drives the dealer's paced play-out (mirroring what the LiveView does one
  # `Process.send_after` tick at a time) to completion, for tests that only
  # care about the final settled state.
  defp play_out_dealer(%Blackjack{status: :dealer_turn} = game),
    do: game |> Blackjack.dealer_step() |> play_out_dealer()

  defp play_out_dealer(%Blackjack{} = game), do: game

  describe "new/1" do
    test "deals two cards to each requested box and two to the dealer" do
      game = Blackjack.new(%{0 => 25, 1 => 50})

      assert length(game.hands) == 2
      assert Enum.map(game.hands, & &1.box) == [0, 1]
      assert Enum.map(game.hands, & &1.bet) == [25, 50]
      assert Enum.all?(game.hands, &(length(&1.cards) == 2))
      assert length(game.dealer_hand) == 2
      assert game.status in [:player_turn, :dealer_turn, :round_over]

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

      case game.status do
        :player_turn ->
          first_active = Enum.find(game.hands, &(&1.status == :active))
          assert game.active_hand == first_active.id

        :dealer_turn ->
          # both boxes happened to be dealt a natural blackjack, and the
          # dealer wasn't - nothing left to play
          assert Enum.all?(game.hands, &(&1.status == :blackjack))
          assert game.active_hand == nil

        :round_over ->
          # the dealer itself was dealt a natural blackjack - the round
          # ends immediately without offering the player any action
          assert Blackjack.blackjack?(game.dealer_hand)
          assert game.active_hand == nil
          assert Enum.all?(game.hands, &(&1.status in [:blackjack, :standing]))
      end
    end
  end

  describe "new/1 when the dealer is dealt a natural blackjack" do
    test "ends the round immediately, settling every hand without any player action" do
      game =
        Stream.repeatedly(fn -> Blackjack.new(%{0 => 25}) end)
        |> Enum.find(&Blackjack.blackjack?(&1.dealer_hand))

      assert game.status == :round_over
      assert game.active_hand == nil
      hand = hd(game.hands)
      assert hand.status in [:blackjack, :standing]
      assert hand.outcome in [:push, :loss]
    end

    test "a hand that hadn't acted yet loses outright, since it can't itself be a natural" do
      game =
        Stream.repeatedly(fn -> Blackjack.new(%{0 => 25}) end)
        |> Enum.find(fn game ->
          Blackjack.blackjack?(game.dealer_hand) and hd(game.hands).outcome == :loss
        end)

      hand = hd(game.hands)
      assert game.status == :round_over
      assert hand.status == :standing
      assert hand.outcome == :loss
      assert hand.payout == 0
    end
  end

  describe "hit/2" do
    test "draws a card into the active hand and stays active if under 21" do
      game = %Blackjack{
        shoe: ["2S", "9S"],
        hands: [
          %{id: 0, box: 0, bet: 25, cards: ["5H", "5D"], status: :active, outcome: nil, payout: nil}
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
          %{id: 0, box: 0, bet: 25, cards: ["10H", "5D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10H", "7D"],
        status: :player_turn
      }

      game = Blackjack.hit(game, 0)
      assert game.status == :dealer_turn

      game = play_out_dealer(game)
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
          %{id: 0, box: 0, bet: 25, cards: ["10H", "10D"], status: :active, outcome: nil, payout: nil}
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
          %{id: 0, box: 0, bet: 25, cards: ["10H", "5D"], status: :active, outcome: nil, payout: nil},
          %{id: 1, box: 1, bet: 25, cards: ["6H", "6D"], status: :active, outcome: nil, payout: nil}
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

  describe "double_down/2" do
    test "doubles the bet, draws exactly one card, and locks the hand in" do
      game = %Blackjack{
        shoe: ["2S", "9S"],
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["6H", "5D"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        dealer_hand: ["7H", "7D"],
        status: :player_turn
      }

      game = Blackjack.double_down(game, 0)
      hand = hd(game.hands)

      assert hand.cards == ["6H", "5D", "2S"]
      assert hand.bet == 50
      assert hand.doubled? == true
      assert hand.status == :standing
      assert game.status == :dealer_turn
      assert game.shoe == ["9S"]
    end

    test "busts if the single extra card pushes the hand over 21" do
      game = %Blackjack{
        shoe: ["KS"],
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["10H", "5D"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        dealer_hand: ["7H", "7D"],
        status: :player_turn
      }

      game = Blackjack.double_down(game, 0) |> play_out_dealer()
      hand = hd(game.hands)

      assert hand.status == :busted
      assert hand.bet == 50
      assert hand.outcome == :loss
      assert hand.payout == 0
    end
  end

  describe "can_double_down?/2" do
    test "true for the active hand's untouched first two cards" do
      game = %Blackjack{
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["6H", "5D"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        status: :player_turn
      }

      assert Blackjack.can_double_down?(game, 0)
    end

    test "false once the hand has already been hit" do
      game = %Blackjack{
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["6H", "5D", "2S"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        status: :player_turn
      }

      refute Blackjack.can_double_down?(game, 0)
    end

    test "false outside the player's turn" do
      game = %Blackjack{
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["6H", "5D"],
            status: :standing,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: nil,
        status: :dealer_turn
      }

      refute Blackjack.can_double_down?(game, 0)
    end
  end

  describe "split/2" do
    test "splits a pair into two hands with matching bets, each dealt one more card" do
      game = %Blackjack{
        shoe: ["2S", "3H", "9C"],
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["8H", "8D"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        dealer_hand: ["7H", "7D"],
        status: :player_turn
      }

      game = Blackjack.split(game, 0)

      assert length(game.hands) == 2
      [hand_a, hand_b] = game.hands

      assert hand_a.cards == ["8H", "2S"]
      assert hand_b.cards == ["8D", "3H"]
      assert hand_a.bet == 25
      assert hand_b.bet == 25
      assert hand_a.split? and hand_b.split?
      assert hand_a.status == :active
      assert hand_b.status == :active
      # play continues on the first resulting hand before moving on
      assert game.active_hand == hand_a.id
      assert game.status == :player_turn
      assert game.shoe == ["9C"]
    end

    test "matches same-value 10-cards (a 10 and a King) as splittable" do
      game = %Blackjack{
        shoe: ["2S", "3H"],
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["10H", "KD"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        dealer_hand: ["7H", "7D"],
        status: :player_turn
      }

      assert Blackjack.can_split?(game, 0)
      game = Blackjack.split(game, 0)
      assert length(game.hands) == 2
    end

    test "splitting Aces deals exactly one card to each and locks them in immediately" do
      game = %Blackjack{
        shoe: ["KS", "9C"],
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["AH", "AD"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        dealer_hand: ["7H", "7D"],
        status: :player_turn
      }

      game = Blackjack.split(game, 0)
      [hand_a, hand_b] = game.hands

      assert hand_a.cards == ["AH", "KS"]
      assert hand_b.cards == ["AD", "9C"]
      # a split-ace 21 doesn't get the natural-blackjack bonus - just standing
      assert hand_a.status == :standing
      assert hand_b.status == :standing
      # both hands are locked in immediately - nothing left to play
      assert game.status == :dealer_turn
      assert game.shoe == []
    end

    test "a split hand can be re-hit, but never split again" do
      game = %Blackjack{
        shoe: ["2S", "3H", "4D"],
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["8H", "8D"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        dealer_hand: ["7H", "7D"],
        status: :player_turn
      }

      game = Blackjack.split(game, 0)
      refute Blackjack.can_split?(game, game.active_hand)

      game = Blackjack.hit(game, game.active_hand)
      assert hd(game.hands).cards == ["8H", "2S", "4D"]
    end
  end

  describe "can_split?/2" do
    test "false for two cards of different value" do
      game = %Blackjack{
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["8H", "9D"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        status: :player_turn
      }

      refute Blackjack.can_split?(game, 0)
    end

    test "false once the hand has three cards" do
      game = %Blackjack{
        hands: [
          %{
            id: 0,
            box: 0,
            bet: 25,
            cards: ["8H", "8D", "2S"],
            status: :active,
            outcome: nil,
            payout: nil,
            split?: false,
            doubled?: false
          }
        ],
        active_hand: 0,
        status: :player_turn
      }

      refute Blackjack.can_split?(game, 0)
    end
  end

  describe "stand/2 and dealer play" do
    test "dealer stands on a soft 17 rather than hitting" do
      game = %Blackjack{
        shoe: ["6H"],
        hands: [
          %{id: 0, box: 0, bet: 25, cards: ["10H", "8D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        # dealer starts on a soft 17 (A + 6) and must stand, not hit
        dealer_hand: ["AS", "6D"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0)
      assert game.status == :dealer_turn
      assert game.dealer_hand == ["AS", "6D"]

      game = play_out_dealer(game)

      assert game.dealer_hand == ["AS", "6D"]
      assert game.status == :round_over
    end

    test "dealer hits until reaching at least 17" do
      game = %Blackjack{
        shoe: ["5S", "9S"],
        hands: [
          %{id: 0, box: 0, bet: 25, cards: ["10H", "8D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["2S", "3S"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0) |> play_out_dealer()

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
          %{id: 0, box: 0, bet: 25, cards: ["10H", "8D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10S", "6C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0) |> play_out_dealer()
      hand = hd(game.hands)

      assert Blackjack.busted?(game.dealer_hand)
      assert hand.outcome == :win
      assert hand.payout == 50
    end

    test "a higher standing total than the dealer's wins 1:1" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{id: 0, box: 0, bet: 25, cards: ["10H", "9D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10S", "8C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0) |> play_out_dealer()
      hand = hd(game.hands)

      assert hand.outcome == :win
      assert hand.payout == 50
    end

    test "equal totals push and return the bet" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{id: 0, box: 0, bet: 25, cards: ["10H", "9D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10S", "9C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0) |> play_out_dealer()
      hand = hd(game.hands)

      assert hand.outcome == :push
      assert hand.payout == 25
    end

    test "a lower standing total than the dealer's loses" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{id: 0, box: 0, bet: 25, cards: ["10H", "7D"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 0,
        dealer_hand: ["10S", "9C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 0) |> play_out_dealer()
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
          %{id: 0, box: 0, bet: 100, cards: ["AS", "KH"], status: :blackjack, outcome: nil, payout: nil},
          %{id: 1, box: 1, bet: 25, cards: ["9S", "5H"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 1,
        dealer_hand: ["10S", "7C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 1) |> play_out_dealer()
      hand = Enum.find(game.hands, &(&1.box == 0))

      assert hand.outcome == :blackjack_win
      # 100 bet returned + 150 winnings = 250 total
      assert hand.payout == 250
    end

    test "a natural blackjack pays 3:2 with floor rounding on an odd bet" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{id: 0, box: 0, bet: 25, cards: ["AS", "KH"], status: :blackjack, outcome: nil, payout: nil},
          %{id: 1, box: 1, bet: 25, cards: ["9S", "5H"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 1,
        dealer_hand: ["10S", "7C"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 1) |> play_out_dealer()
      hand = Enum.find(game.hands, &(&1.box == 0))

      assert hand.outcome == :blackjack_win
      # bet 25 + floor(25 * 3 / 2) = 25 + 37 = 62, not 62.5/63
      assert hand.payout == 62
    end

    test "a natural blackjack pushes against a dealer natural blackjack" do
      game = %Blackjack{
        shoe: [],
        hands: [
          %{id: 0, box: 0, bet: 100, cards: ["AS", "KH"], status: :blackjack, outcome: nil, payout: nil},
          %{id: 1, box: 1, bet: 25, cards: ["9S", "5H"], status: :active, outcome: nil, payout: nil}
        ],
        active_hand: 1,
        dealer_hand: ["AH", "KD"],
        status: :player_turn
      }

      game = Blackjack.stand(game, 1) |> play_out_dealer()
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
            id: 0,
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

      game = Blackjack.stand(game, 0) |> play_out_dealer()
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
          case game.status do
            :player_turn ->
              if Enum.random([true, false]),
                do: Blackjack.hit(game, game.active_hand),
                else: Blackjack.stand(game, game.active_hand)

            :dealer_turn ->
              Blackjack.dealer_step(game)

            :round_over ->
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
