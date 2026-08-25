defmodule HighSociety.GamesTest do
  use HighSociety.DataCase, async: true

  alias HighSociety.Games

  import HighSociety.AccountsFixtures

  setup do
    %{scope: user_scope_fixture()}
  end

  describe "start_war_game/1" do
    test "deals a fresh 26/26 game for the user", %{scope: scope} do
      war_game = Games.start_war_game(scope)

      assert war_game.user_id == scope.user.id
      assert war_game.status == "in_progress"
      assert length(war_game.player_deck) == 26
      assert length(war_game.computer_deck) == 26
      assert war_game.round_number == 0
    end

    test "discards any previous in-progress game for the user", %{scope: scope} do
      first = Games.start_war_game(scope)
      second = Games.start_war_game(scope)

      assert first.id != second.id
      assert Games.get_active_war_game(scope).id == second.id
      refute HighSociety.Repo.get(Games.WarGame, first.id)
    end
  end

  describe "get_active_war_game/1" do
    test "returns nil when the user has no game", %{scope: scope} do
      assert Games.get_active_war_game(scope) == nil
    end

    test "returns the user's in-progress game", %{scope: scope} do
      war_game = Games.start_war_game(scope)
      assert Games.get_active_war_game(scope).id == war_game.id
    end

    test "does not return another user's game", %{scope: scope} do
      Games.start_war_game(scope)
      other_scope = user_scope_fixture()

      assert Games.get_active_war_game(other_scope) == nil
    end
  end

  describe "play_round/1" do
    test "advances the game and persists the new state", %{scope: scope} do
      war_game = Games.start_war_game(scope)

      updated = Games.play_round(war_game)

      assert updated.round_number == 1
      assert updated.last_round != nil
      assert length(updated.player_deck) + length(updated.computer_deck) == 52

      persisted = HighSociety.Repo.get!(Games.WarGame, war_game.id)
      assert persisted.player_deck == updated.player_deck
      assert persisted.computer_deck == updated.computer_deck
      assert persisted.last_round == updated.last_round
    end

    test "playing to completion ends the game with a winner and 52 cards conserved", %{
      scope: scope
    } do
      war_game = Games.start_war_game(scope)

      final =
        war_game
        |> Stream.iterate(&Games.play_round/1)
        |> Enum.find(&(&1.status != "in_progress"))

      assert final.status in ["player_won", "computer_won"]
      assert length(final.player_deck) + length(final.computer_deck) == 52
    end
  end
end
