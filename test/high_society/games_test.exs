defmodule HighSociety.GamesTest do
  use HighSociety.DataCase, async: true

  alias HighSociety.Accounts
  alias HighSociety.Games
  alias HighSociety.Games.Blackjack

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
      # a tie leaves some cards held in a pending war's pot, off both decks,
      # until the tiebreaker is flipped - so conservation must account for it
      pending_pot_size = (updated.pending_war && length(updated.pending_war["pot"])) || 0
      assert length(updated.player_deck) + length(updated.computer_deck) + pending_pot_size == 52

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

  describe "start_blackjack_round/2" do
    test "debits the total bet and deals a fresh round", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}

      assert {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500, 1 => 5_000})

      assert game.user_id == scope.user.id
      assert length(game.hands) == 2

      assert HighSociety.Repo.get!(HighSociety.Accounts.User, user.id).balance ==
               Accounts.starting_chip_amount() - 7_500
    end

    test "rejects an empty bet map", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}

      assert {:error, :no_bets} = Games.start_blackjack_round(scope, %{0 => 0, 1 => 0})
      assert Games.get_active_blackjack_game(scope) == nil
    end

    test "rejects a bet over the $500 max, leaving balance and DB untouched", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}

      assert {:error, :bet_too_large} =
               Games.start_blackjack_round(scope, %{0 => Blackjack.max_bet() + 1})

      assert HighSociety.Repo.get!(HighSociety.Accounts.User, user.id).balance ==
               Accounts.starting_chip_amount()

      assert Games.get_active_blackjack_game(scope) == nil
    end

    test "rejects a total bet exceeding the user's balance", %{scope: scope} do
      assert scope.user.balance == 0
      assert {:error, :insufficient_funds} = Games.start_blackjack_round(scope, %{0 => 2_500})
      assert Games.get_active_blackjack_game(scope) == nil
    end

    test "discards any previous round for the user", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}

      {:ok, first} = Games.start_blackjack_round(scope, %{0 => 2_500})
      {:ok, second} = Games.start_blackjack_round(scope, %{0 => 2_500})

      assert first.id != second.id
      refute HighSociety.Repo.get(Games.BlackjackGame, first.id)
    end
  end

  describe "get_active_blackjack_game/1" do
    test "returns nil when the user has never played", %{scope: scope} do
      assert Games.get_active_blackjack_game(scope) == nil
    end

    test "returns the latest round for the user regardless of status", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}

      {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})
      assert Games.get_active_blackjack_game(scope).id == game.id
    end

    test "does not return another user's round", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}
      Games.start_blackjack_round(scope, %{0 => 2_500})

      other_scope = user_scope_fixture()
      assert Games.get_active_blackjack_game(other_scope) == nil
    end
  end

  describe "hit/2 and stand/2" do
    test "standing advances the round, persists it, and credits a winning payout", %{
      scope: scope
    } do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}
      {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

      # rig the persisted round so standing immediately wins against a
      # dealer bust, for a deterministic payout assertion
      game =
        game
        |> Games.BlackjackGame.changeset(%{
          status: "player_turn",
          shoe: ["KS"],
          hands: [
            %{
              "id" => 0,
              "box" => 0,
              "bet" => 2_500,
              "cards" => ["10H", "9D"],
              "status" => "active",
              "outcome" => nil,
              "payout" => nil
            }
          ],
          active_hand: 0,
          dealer_hand: ["10S", "6C"]
        })
        |> HighSociety.Repo.update!()

      {updated_game, updated_user} = Games.stand(scope, game)
      assert updated_game.status == "dealer_turn"

      {updated_game, updated_user} =
        Stream.iterate({updated_game, updated_user}, fn {game, _user} ->
          Games.dealer_step(scope, game)
        end)
        |> Enum.find(fn {game, _user} -> game.status == "round_over" end)

      assert updated_game.status == "round_over"
      hand = hd(updated_game.hands)
      assert hand["outcome"] == "win"
      assert hand["payout"] == 5_000

      balance_after_bet = Accounts.starting_chip_amount() - 2_500
      assert updated_user.balance == balance_after_bet + 5_000

      assert HighSociety.Repo.get!(HighSociety.Accounts.User, user.id).balance ==
               updated_user.balance
    end

    test "hitting persists the drawn card without crediting balance mid-round", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}
      {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})
      # start_blackjack_round debited the bet - refresh the scope the same
      # way the LiveView does after every balance-moving call
      scope = %{scope | user: Accounts.get_user!(user.id)}

      game =
        game
        |> Games.BlackjackGame.changeset(%{
          status: "player_turn",
          shoe: ["2S"],
          hands: [
            %{
              "id" => 0,
              "box" => 0,
              "bet" => 2_500,
              "cards" => ["5H", "5D"],
              "status" => "active",
              "outcome" => nil,
              "payout" => nil
            }
          ],
          active_hand: 0,
          dealer_hand: ["7H", "7D"]
        })
        |> HighSociety.Repo.update!()

      balance_before = Accounts.starting_chip_amount() - 2_500
      {updated_game, updated_user} = Games.hit(scope, game)

      assert updated_game.status == "player_turn"
      assert hd(updated_game.hands)["cards"] == ["5H", "5D", "2S"]
      assert updated_user.balance == balance_before
    end
  end

  describe "double_down/2" do
    test "debits the matching extra bet, doubles the hand, and draws one card", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}
      {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})
      scope = %{scope | user: Accounts.get_user!(user.id)}

      game =
        game
        |> Games.BlackjackGame.changeset(%{
          status: "player_turn",
          shoe: ["2S"],
          hands: [
            %{
              "id" => 0,
              "box" => 0,
              "bet" => 2_500,
              "cards" => ["6H", "5D"],
              "status" => "active",
              "outcome" => nil,
              "payout" => nil
            }
          ],
          active_hand: 0,
          dealer_hand: ["7H", "7D"]
        })
        |> HighSociety.Repo.update!()

      balance_before_double = Accounts.starting_chip_amount() - 2_500
      assert {:ok, updated_game, updated_user} = Games.double_down(scope, game)

      hand = hd(updated_game.hands)
      assert hand["cards"] == ["6H", "5D", "2S"]
      assert hand["bet"] == 5_000
      assert hand["doubled"] == true
      assert updated_game.status == "dealer_turn"
      assert updated_user.balance == balance_before_double - 2_500

      assert HighSociety.Repo.get!(HighSociety.Accounts.User, user.id).balance ==
               updated_user.balance
    end

    test "rejects doubling down without enough balance to match the bet, leaving the game untouched",
         %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}
      {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})
      scope = %{scope | user: Accounts.get_user!(user.id)}

      # rig a plain 2-card active hand deterministically - the random deal
      # would otherwise occasionally land a natural blackjack instead
      game =
        game
        |> Games.BlackjackGame.changeset(%{
          status: "player_turn",
          hands: [
            %{
              "id" => 0,
              "box" => 0,
              "bet" => 2_500,
              "cards" => ["6H", "5D"],
              "status" => "active",
              "outcome" => nil,
              "payout" => nil
            }
          ],
          active_hand: 0
        })
        |> HighSociety.Repo.update!()

      # drain the user down to less than the bet, so the matching extra bet
      # required to double down can't be covered
      {:ok, poor_user} = Accounts.adjust_balance(scope.user, -(scope.user.balance - 10))
      scope = %{scope | user: poor_user}

      assert {:error, :insufficient_funds} = Games.double_down(scope, game)
      assert Games.get_active_blackjack_game(scope).active_hand == game.active_hand
      assert Accounts.get_user!(user.id).balance == poor_user.balance
    end

    test "rejects doubling down once the hand has already been hit", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}
      {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})
      scope = %{scope | user: Accounts.get_user!(user.id)}

      game =
        game
        |> Games.BlackjackGame.changeset(%{
          status: "player_turn",
          shoe: ["2S"],
          hands: [
            %{
              "id" => 0,
              "box" => 0,
              "bet" => 2_500,
              "cards" => ["6H", "5D", "2S"],
              "status" => "active",
              "outcome" => nil,
              "payout" => nil
            }
          ],
          active_hand: 0,
          dealer_hand: ["7H", "7D"]
        })
        |> HighSociety.Repo.update!()

      assert {:error, :invalid_action} = Games.double_down(scope, game)
      assert Accounts.get_user!(user.id).balance == scope.user.balance
    end
  end

  describe "split/2" do
    test "debits a matching bet and deals each resulting hand one card", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}
      {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})
      scope = %{scope | user: Accounts.get_user!(user.id)}

      game =
        game
        |> Games.BlackjackGame.changeset(%{
          status: "player_turn",
          shoe: ["2S", "3H"],
          hands: [
            %{
              "id" => 0,
              "box" => 0,
              "bet" => 2_500,
              "cards" => ["8H", "8D"],
              "status" => "active",
              "outcome" => nil,
              "payout" => nil
            }
          ],
          active_hand: 0,
          dealer_hand: ["7H", "7D"]
        })
        |> HighSociety.Repo.update!()

      balance_before_split = Accounts.starting_chip_amount() - 2_500
      assert {:ok, updated_game, updated_user} = Games.split(scope, game)

      assert length(updated_game.hands) == 2
      assert Enum.map(updated_game.hands, & &1["bet"]) == [2_500, 2_500]
      assert Enum.map(updated_game.hands, & &1["cards"]) == [["8H", "2S"], ["8D", "3H"]]
      assert updated_user.balance == balance_before_split - 2_500

      assert HighSociety.Repo.get!(HighSociety.Accounts.User, user.id).balance ==
               updated_user.balance
    end

    test "rejects splitting without enough balance to match the bet, leaving the game untouched",
         %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}
      {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})
      scope = %{scope | user: Accounts.get_user!(user.id)}

      # rig a splittable pair deterministically - the random deal would
      # otherwise only rarely land a same-value pair
      game =
        game
        |> Games.BlackjackGame.changeset(%{
          status: "player_turn",
          hands: [
            %{
              "id" => 0,
              "box" => 0,
              "bet" => 2_500,
              "cards" => ["8H", "8D"],
              "status" => "active",
              "outcome" => nil,
              "payout" => nil
            }
          ],
          active_hand: 0
        })
        |> HighSociety.Repo.update!()

      {:ok, poor_user} = Accounts.adjust_balance(scope.user, -(scope.user.balance - 10))
      scope = %{scope | user: poor_user}

      assert {:error, :insufficient_funds} = Games.split(scope, game)
      assert length(Games.get_active_blackjack_game(scope).hands) == 1
      assert Accounts.get_user!(user.id).balance == poor_user.balance
    end

    test "rejects splitting two cards of different value", %{scope: scope} do
      {:ok, user} = Accounts.claim_starting_chips(scope.user)
      scope = %{scope | user: user}
      {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})
      scope = %{scope | user: Accounts.get_user!(user.id)}

      game =
        game
        |> Games.BlackjackGame.changeset(%{
          status: "player_turn",
          shoe: ["2S", "3H"],
          hands: [
            %{
              "id" => 0,
              "box" => 0,
              "bet" => 2_500,
              "cards" => ["8H", "9D"],
              "status" => "active",
              "outcome" => nil,
              "payout" => nil
            }
          ],
          active_hand: 0,
          dealer_hand: ["7H", "7D"]
        })
        |> HighSociety.Repo.update!()

      assert {:error, :invalid_action} = Games.split(scope, game)
      assert Accounts.get_user!(user.id).balance == scope.user.balance
    end
  end
end
