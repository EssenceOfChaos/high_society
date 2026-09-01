defmodule HighSociety.Games.BattleshipMatchTest do
  # Unlike Poker's tables, each match here is its own short-lived process
  # created fresh per test - but every mutation it makes still goes
  # through `Repo` from a different (dynamically-spawned) process than
  # the test itself, so this still needs the shared sandbox connection
  # `async: false` grants (see `HighSociety.DataCase.setup_sandbox/1`),
  # exactly like `PokerTableTest`.
  use HighSociety.DataCase, async: false

  alias HighSociety.Accounts
  alias HighSociety.BattleshipFixtures
  alias HighSociety.Games.BattleshipMatch

  import HighSociety.BattleshipFixtures

  describe "create/2" do
    test "debits the wager and starts a waiting match" do
      creator = funded_user()
      assert {:ok, slug} = BattleshipMatch.create(creator, 100)
      stop_match_after_test!(slug)

      view = BattleshipMatch.get_state(slug)
      assert view.status == :waiting_for_opponent
      assert view.seats[0].user_id == creator.id
      assert view.seats[1] == nil

      assert Accounts.get_user!(creator.id).balance == 10_000 - 100
    end

    test "rejects a wager the creator can't afford" do
      poor_user = BattleshipFixtures.funded_user(0)
      assert BattleshipMatch.create(poor_user, 100) == {:error, :insufficient_funds}
    end
  end

  describe "join/2" do
    test "seats the second player, debits their wager, and starts placement" do
      creator = funded_user()
      joiner = funded_user()
      slug = create_match_for_test!(creator, 100)

      assert {:ok, view} = BattleshipMatch.join(slug, joiner)
      assert view.status == :placing_fleets
      assert view.seats[1].user_id == joiner.id
      assert Accounts.get_user!(joiner.id).balance == 10_000 - 100
    end

    test "rejects a third player" do
      creator = funded_user()
      joiner = funded_user()
      bystander = funded_user()
      slug = create_match_for_test!(creator, 100)

      {:ok, _view} = BattleshipMatch.join(slug, joiner)
      assert BattleshipMatch.join(slug, bystander) == {:error, :match_full}
    end

    test "rejects the creator joining their own match" do
      creator = funded_user()
      slug = create_match_for_test!(creator, 100)
      assert BattleshipMatch.join(slug, creator) == {:error, :already_seated}
    end

    test "rejects a joiner who can't afford the wager" do
      creator = funded_user()
      poor_joiner = BattleshipFixtures.funded_user(0)
      slug = create_match_for_test!(creator, 100)

      assert BattleshipMatch.join(slug, poor_joiner) == {:error, :insufficient_funds}
    end
  end

  describe "cancel/2" do
    test "refunds the creator's wager and ends the match while still waiting" do
      creator = funded_user()
      slug = create_match_for_test!(creator, 100)
      balance_before = Accounts.get_user!(creator.id).balance

      assert {:ok, view} = BattleshipMatch.cancel(slug, creator.id)
      assert view.status == :cancelled
      assert Accounts.get_user!(creator.id).balance == balance_before + 100

      Process.sleep(10)
      assert GenServer.whereis(BattleshipMatch.via(slug)) == nil
    end

    test "rejects cancellation from anyone but the creator" do
      creator = funded_user()
      bystander = funded_user()
      slug = create_match_for_test!(creator, 100)

      assert BattleshipMatch.cancel(slug, bystander.id) == {:error, :not_seated}
    end

    test "rejects cancellation once an opponent has joined" do
      creator = funded_user()
      joiner = funded_user()
      slug = create_match_for_test!(creator, 100)
      {:ok, _view} = BattleshipMatch.join(slug, joiner)

      assert BattleshipMatch.cancel(slug, creator.id) == {:error, :already_started}
    end
  end

  describe "placement" do
    setup do
      creator = funded_user()
      joiner = funded_user()
      slug = create_match_for_test!(creator, 100)
      {:ok, _view} = BattleshipMatch.join(slug, joiner)
      %{slug: slug, creator: creator, joiner: joiner}
    end

    test "rejects placement from someone not seated", %{slug: slug} do
      bystander = funded_user()

      assert BattleshipMatch.place_ship(slug, bystander.id, :destroyer, {0, 0}, :horizontal) ==
               {:error, :not_seated}
    end

    test "randomize_fleet/2 gives that seat a complete fleet", %{slug: slug, creator: creator} do
      assert {:ok, view} = BattleshipMatch.randomize_fleet(slug, creator.id)
      assert length(view.battleship.player_fleet) == 5
    end

    test "clear_fleet/2 empties that seat's fleet without touching the other seat's", %{
      slug: slug,
      creator: creator,
      joiner: joiner
    } do
      {:ok, _view} = BattleshipMatch.randomize_fleet(slug, creator.id)
      {:ok, _view} = BattleshipMatch.randomize_fleet(slug, joiner.id)

      assert {:ok, view} = BattleshipMatch.clear_fleet(slug, creator.id)
      assert view.battleship.player_fleet == []
      assert length(view.battleship.opponent_fleet) == 5
    end

    test "ready_up/2 starts the match once both seats are ready", %{
      slug: slug,
      creator: creator,
      joiner: joiner
    } do
      ready_with_random_fleet!(slug, creator.id)
      view = ready_with_random_fleet!(slug, joiner.id)

      assert view.status in [:player_turn, :opponent_turn]
    end
  end

  describe "fire/3 and forfeit/2" do
    setup do
      creator = funded_user()
      joiner = funded_user()
      slug = create_match_for_test!(creator, 100)
      {:ok, _view} = BattleshipMatch.join(slug, joiner)
      ready_with_random_fleet!(slug, creator.id)
      view = ready_with_random_fleet!(slug, joiner.id)

      firer = if view.status == :player_turn, do: creator, else: joiner
      waiter = if firer.id == creator.id, do: joiner, else: creator

      %{slug: slug, firer: firer, waiter: waiter}
    end

    test "resolves a shot and flips turn to the other seat", %{slug: slug, firer: firer} do
      assert {:ok, view} = BattleshipMatch.fire(slug, firer.id, {0, 0})
      assert view.last_shot.side in [:player, :opponent]
      assert view.status in [:player_turn, :opponent_turn, :player_won, :opponent_won]
    end

    test "rejects firing out of turn", %{slug: slug, waiter: waiter} do
      assert BattleshipMatch.fire(slug, waiter.id, {0, 0}) == {:error, :not_your_turn}
    end

    test "forfeit/2 ends the match and pays the other seat the full pot", %{
      slug: slug,
      firer: firer,
      waiter: waiter
    } do
      firer_balance_before = Accounts.get_user!(firer.id).balance
      waiter_balance_before = Accounts.get_user!(waiter.id).balance

      assert {:ok, view} = BattleshipMatch.forfeit(slug, firer.id)
      assert view.status == :forfeited

      assert Accounts.get_user!(waiter.id).balance == waiter_balance_before + 200
      assert Accounts.get_user!(firer.id).balance == firer_balance_before

      # The match should have stopped itself.
      Process.sleep(10)
      assert GenServer.whereis(BattleshipMatch.via(slug)) == nil
    end
  end
end
