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

    test "a tie triggers a war, burning three cards each before the decider" do
      game = %War{
        player_deck: ["5S", "1", "2", "3", "9S"],
        computer_deck: ["5H", "a", "b", "c", "2H"],
        status: :in_progress
      }

      game = War.play_round(game)

      assert game.last_round.war? == true
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
