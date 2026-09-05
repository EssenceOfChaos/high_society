defmodule HighSociety.Games.PokerTableTest do
  # Poker tables are long-lived, application-wide GenServers rather than
  # per-test state, so these tests can't run concurrently with each other
  # (or anything else touching the same table) - see `PokerFixtures`.
  use HighSociety.DataCase, async: false

  alias HighSociety.Accounts
  alias HighSociety.AccountsFixtures
  alias HighSociety.Games.PokerTable
  alias HighSociety.PokerFixtures

  @slug "new-york"

  setup do
    PokerFixtures.reset_table_around_test!(@slug)
    :ok
  end

  defp funded_user(balance) do
    user = AccountsFixtures.user_fixture()
    {:ok, user} = Accounts.adjust_balance(user, balance)
    user
  end

  describe "sit/4" do
    test "debits the buy-in from the user's balance and seats them" do
      user = funded_user(100_000)

      assert {:ok, view} = PokerTable.sit(@slug, user, 0, 20_000)
      assert view.seats[0].user_id == user.id
      assert view.seats[0].stack == 20_000

      assert Accounts.get_user!(user.id).balance == 80_000
    end

    test "rejects a buy-in outside the table's range" do
      user = funded_user(1_000_000)
      assert {:error, :invalid_buy_in} = PokerTable.sit(@slug, user, 0, 1)
    end

    test "rejects sitting down without enough balance" do
      user = funded_user(1_000)
      assert {:error, :insufficient_funds} = PokerTable.sit(@slug, user, 0, 4_000)
    end

    test "rejects a seat that's already taken" do
      user1 = funded_user(100_000)
      user2 = funded_user(100_000)
      {:ok, _view} = PokerTable.sit(@slug, user1, 0, 20_000)
      assert {:error, :seat_taken} = PokerTable.sit(@slug, user2, 0, 20_000)
    end

    test "a second player sitting down deals a hand" do
      user1 = funded_user(100_000)
      user2 = funded_user(100_000)
      {:ok, _view} = PokerTable.sit(@slug, user1, 0, 20_000)
      assert {:ok, view} = PokerTable.sit(@slug, user2, 1, 20_000)

      assert view.hand.status == :in_progress
      assert map_size(view.hand.seats) == 2
    end
  end

  describe "stand/2" do
    test "credits the current stack back to the user's balance" do
      user = funded_user(100_000)
      {:ok, _view} = PokerTable.sit(@slug, user, 0, 20_000)

      assert {:ok, view} = PokerTable.stand(@slug, user.id)
      refute Map.has_key?(view.seats, 0)
      assert Accounts.get_user!(user.id).balance == 100_000
    end

    test "folds the player's live hand immediately when standing up mid-hand" do
      user1 = funded_user(100_000)
      user2 = funded_user(100_000)
      {:ok, _view} = PokerTable.sit(@slug, user1, 0, 20_000)
      {:ok, _view} = PokerTable.sit(@slug, user2, 1, 20_000)

      assert {:ok, view} = PokerTable.stand(@slug, user1.id)
      assert map_size(view.seats) == 1

      # user1 gets back whatever remained of their stack after posting/folding
      updated_balance = Accounts.get_user!(user1.id).balance
      assert updated_balance >= 80_000 - 20_000 and updated_balance <= 80_000 + 20_000
    end

    test "returns an error for a user who isn't seated" do
      user = funded_user(100_000)
      assert {:error, :not_seated} = PokerTable.stand(@slug, user.id)
    end
  end

  describe "act/4" do
    test "rejects an action from a user with no seat" do
      user = funded_user(100_000)
      assert {:error, :not_seated} = PokerTable.act(@slug, user.id, :check)
    end

    test "rejects an action when no hand is in progress" do
      user = funded_user(100_000)
      {:ok, _view} = PokerTable.sit(@slug, user, 0, 20_000)
      assert {:error, :no_hand_in_progress} = PokerTable.act(@slug, user.id, :check)
    end

    test "a legal action updates the table state" do
      user1 = funded_user(100_000)
      user2 = funded_user(100_000)
      {:ok, _view} = PokerTable.sit(@slug, user1, 0, 20_000)
      {:ok, view} = PokerTable.sit(@slug, user2, 1, 20_000)

      acting_user = if view.hand.action_on == 0, do: user1, else: user2

      assert {:ok, updated} = PokerTable.act(@slug, acting_user.id, :fold)
      assert updated.hand.status == :hand_over
    end

    test "rejects an out-of-turn action" do
      user1 = funded_user(100_000)
      user2 = funded_user(100_000)
      {:ok, _view} = PokerTable.sit(@slug, user1, 0, 20_000)
      {:ok, view} = PokerTable.sit(@slug, user2, 1, 20_000)

      waiting_user = if view.hand.action_on == 0, do: user2, else: user1

      assert {:error, :not_your_turn} = PokerTable.act(@slug, waiting_user.id, :fold)
    end
  end
end
