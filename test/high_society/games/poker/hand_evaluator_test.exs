defmodule HighSociety.Games.Poker.HandEvaluatorTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.Poker.HandEvaluator

  describe "rank/1" do
    test "ranks a high card hand" do
      assert HandEvaluator.rank(~w(2S 5D 9C JH KD 3H 7C)) == {0, [13, 11, 9, 7, 5]}
    end

    test "ranks a pair, with kickers picked from the rest of the hand" do
      assert HandEvaluator.rank(~w(2S 2D 9C JH KD 3H 7C)) == {1, [2, 13, 11, 9]}
    end

    test "ranks two pair, ordered high pair then low pair then kicker" do
      assert HandEvaluator.rank(~w(2S 2D 9C 9H KD 3H 7C)) == {2, [9, 2, 13]}
    end

    test "ranks three of a kind" do
      assert HandEvaluator.rank(~w(2S 2D 2C 9H KD 3H 7C)) == {3, [2, 13, 9]}
    end

    test "ranks a straight" do
      assert HandEvaluator.rank(~w(4S 5D 6C 7H 8D 2H KC)) == {4, [8]}
    end

    test "ranks the wheel (A-2-3-4-5) as a five-high straight" do
      assert HandEvaluator.rank(~w(AS 2D 3C 4H 5D 9H KC)) == {4, [5]}
    end

    test "a six-high straight beats the wheel" do
      assert HandEvaluator.rank(~w(4S 5D 6C 7H 8D 2H KC)) >
               HandEvaluator.rank(~w(AS 2D 3C 4H 5D 9H KC))
    end

    test "ranks a flush" do
      assert HandEvaluator.rank(~w(2S 5S 9S JS KS 3H 7C)) == {5, [13, 11, 9, 5, 2]}
    end

    test "ranks a full house, trips value then pair value" do
      assert HandEvaluator.rank(~w(2S 2D 2C 9H 9D 3H 7C)) == {6, [2, 9]}
    end

    test "ranks four of a kind" do
      assert HandEvaluator.rank(~w(2S 2D 2C 2H 9D 3H 7C)) == {7, [2, 9]}
    end

    test "ranks a straight flush" do
      assert HandEvaluator.rank(~w(4S 5S 6S 7S 8S 2H KC)) == {8, [8]}
    end

    test "every category outranks the one below it" do
      straight_flush = HandEvaluator.rank(~w(4S 5S 6S 7S 8S 2H KC))
      quads = HandEvaluator.rank(~w(2S 2D 2C 2H 9D 3H 7C))
      full_house = HandEvaluator.rank(~w(2S 2D 2C 9H 9D 3H 7C))
      flush = HandEvaluator.rank(~w(2S 5S 9S JS KS 3H 7C))
      straight = HandEvaluator.rank(~w(4S 5D 6C 7H 8D 2H KC))
      trips = HandEvaluator.rank(~w(2S 2D 2C 9H KD 3H 7C))
      two_pair = HandEvaluator.rank(~w(2S 2D 9C 9H KD 3H 7C))
      pair = HandEvaluator.rank(~w(2S 2D 9C JH KD 3H 7C))
      high_card = HandEvaluator.rank(~w(2S 5D 9C JH KD 3H 7C))

      assert straight_flush > quads
      assert quads > full_house
      assert full_house > flush
      assert flush > straight
      assert straight > trips
      assert trips > two_pair
      assert two_pair > pair
      assert pair > high_card
    end

    test "two hands that both just play the board tie" do
      hand_a = ~w(2S 3D 4C 5H 6S 9H KC)
      hand_b = ~w(2S 3D 4C 5H 6S 8D QC)

      assert HandEvaluator.rank(hand_a) == HandEvaluator.rank(hand_b)
    end
  end
end
