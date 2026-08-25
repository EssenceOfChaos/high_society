defmodule HighSociety.Games.WarTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.War

  describe "new/0" do
    test "deals a full 52 card deck evenly between player and computer" do
      game = War.new()

      assert length(game.player_deck) == 26
      assert length(game.computer_deck) == 26
      assert game.status == :in_progress
      assert game.last_round == nil

      all_cards = game.player_deck ++ game.computer_deck
      assert length(Enum.uniq(all_cards)) == 52
    end
  end

  describe "play_round/1" do
    test "the higher card wins the round and takes both cards" do
      game = %War{player_deck: ["AS", "2S"], computer_deck: ["2H", "3H"], status: :in_progress}

      game = War.play_round(game)

      assert game.last_round.winner == :player
      assert game.last_round.player_card == "AS"
      assert game.last_round.computer_card == "2H"
      assert game.last_round.cards_won == 2
      assert game.last_round.war? == false
      # the won pot is shuffled before rejoining the deck, so only the
      # membership (not the order) is guaranteed
      assert Enum.sort(game.player_deck) == Enum.sort(["2S", "AS", "2H"])
      assert game.computer_deck == ["3H"]
      assert game.status == :in_progress
    end

    test "a tie declares a war and burns three cards each, but leaves the tiebreaker pending" do
      game = %War{
        player_deck: ["5S", "1", "2", "3", "9S"],
        computer_deck: ["5H", "a", "b", "c", "2H"],
        status: :in_progress
      }

      game = War.play_round(game)

      assert game.status == :in_progress
      assert game.last_round.war? == true
      assert game.last_round.pending? == true
      assert game.last_round.player_card == nil
      assert game.last_round.computer_card == nil
      assert game.last_round.winner == nil
      assert game.last_round.ties == [%{player_card: "5S", computer_card: "5H"}]
      # the tied cards plus three burned each are held in the pot, awaiting the tiebreaker
      assert game.player_deck == ["9S"]
      assert game.computer_deck == ["2H"]
      assert game.war.pot == ["5S", "5H", "1", "2", "3", "a", "b", "c"]

      game = War.play_round(game)

      assert game.war == nil
      assert game.last_round.war? == true
      assert game.last_round.pending? == false
      assert game.last_round.player_card == "9S"
      assert game.last_round.computer_card == "2H"
      assert game.last_round.winner == :player
      assert game.last_round.ties == [%{player_card: "5S", computer_card: "5H"}]
      # 5S + 5H + 1,2,3 + a,b,c + 9S + 2H = 10 cards, all won by the player
      assert game.last_round.cards_won == 10
      assert length(game.player_deck) == 10
      assert game.computer_deck == []
      assert game.status == :player_won
    end

    test "a tiebreaker that ties again chains into a second war" do
      game = %War{
        player_deck: ["5S", "1", "2", "3", "5D", "4", "5", "6", "8S"],
        computer_deck: ["5H", "a", "b", "c", "5C", "d", "e", "f", "9H"],
        status: :in_progress
      }

      # round 1: 5S/5H tie, burns three each, leaves war #1 pending
      game = War.play_round(game)
      assert game.status == :in_progress
      assert game.last_round.pending? == true
      assert length(game.last_round.ties) == 1

      # round 2: the war #1 tiebreaker (5D/5C) ties again, chaining into war #2
      game = War.play_round(game)
      assert game.status == :in_progress
      assert game.last_round.pending? == true
      assert game.last_round.war? == true
      assert length(game.last_round.ties) == 2
      assert game.player_deck == ["8S"]
      assert game.computer_deck == ["9H"]

      # round 3: the war #2 tiebreaker (8S/9H) finally decides it
      game = War.play_round(game)

      assert game.status == :computer_won
      assert game.last_round.pending? == false
      assert game.last_round.winner == :computer
      assert game.last_round.cards_won == 18
      assert game.player_deck == []
    end

    test "conserves all 52 cards and always terminates, across many full games" do
      for _ <- 1..50 do
        final =
          War.new()
          |> Stream.iterate(&War.play_round/1)
          |> Enum.find(&(&1.status != :in_progress))

        assert length(final.player_deck) + length(final.computer_deck) == 52
        assert final.status in [:player_won, :computer_won]

        if final.status == :player_won do
          assert length(final.computer_deck) == 0
        else
          assert length(final.player_deck) == 0
        end
      end
    end

    test "a player who runs out of cards mid-war loses, and the pot is still conserved" do
      # player only has 2 cards left when the tie forces a war they can't fund
      game = %War{
        player_deck: ["5S", "9S"],
        computer_deck: ["5H", "a", "b", "c", "2H"],
        status: :in_progress
      }

      game = War.play_round(game)

      assert game.status == :computer_won
      assert game.player_deck == []
      # pot is 5S, 5H, 9S + burned a, b, c = 6 cards, plus the "2H" the
      # computer never had to play = 7 cards total, and nothing is lost
      assert game.last_round.cards_won == 6
      assert length(game.computer_deck) == 7
    end
  end
end
