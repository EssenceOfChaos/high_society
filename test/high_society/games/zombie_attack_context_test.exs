defmodule HighSociety.Games.ZombieAttackContextTest do
  use HighSociety.DataCase, async: true

  alias HighSociety.Accounts
  alias HighSociety.Games.ZombieAttack
  alias HighSociety.Games.ZombieAttackContext
  alias HighSociety.Games.ZombieAttackGame
  alias HighSociety.Repo

  import HighSociety.AccountsFixtures

  setup do
    {:ok, user} = user_scope_fixture().user |> Accounts.claim_zombie_attack_tokens()
    %{scope: user_scope_fixture(user)}
  end

  describe "start_zombie_attack_game/2" do
    test "debits the wager and generates a full wave schedule", %{scope: scope} do
      assert {:ok, game} = ZombieAttackContext.start_zombie_attack_game(scope, 100)

      assert game.user_id == scope.user.id
      assert game.wager == 100
      assert game.status == "in_progress"
      assert game.wave_reached == 0
      assert length(game.wave_schedule) == ZombieAttack.wave_count()

      assert Accounts.get_user!(scope.user.id).tokens_balance ==
               Accounts.zombie_attack_starting_token_amount() - 100
    end

    test "rejects a wager the user can't afford" do
      scope = user_scope_fixture()

      assert ZombieAttackContext.start_zombie_attack_game(scope, 100) ==
               {:error, :insufficient_funds}
    end

    test "rejects a wager above the max", %{scope: scope} do
      assert ZombieAttackContext.start_zombie_attack_game(scope, ZombieAttack.max_wager() + 1) ==
               {:error, :wager_too_high}
    end

    test "discards any previous unresolved game for the user", %{scope: scope} do
      {:ok, first} = ZombieAttackContext.start_zombie_attack_game(scope, 50)
      {:ok, second} = ZombieAttackContext.start_zombie_attack_game(scope, 50)

      assert first.id != second.id
      refute Repo.get(ZombieAttackGame, first.id)
    end
  end

  describe "get_active_zombie_attack_game/1" do
    test "returns nil with no game", %{scope: scope} do
      assert ZombieAttackContext.get_active_zombie_attack_game(scope) == nil
    end

    test "returns the user's unresolved game", %{scope: scope} do
      {:ok, game} = ZombieAttackContext.start_zombie_attack_game(scope, 50)
      assert ZombieAttackContext.get_active_zombie_attack_game(scope).id == game.id
    end
  end

  describe "report_wave_cleared/3" do
    test "accepts the next wave in sequence", %{scope: scope} do
      {:ok, game} = ZombieAttackContext.start_zombie_attack_game(scope, 100)
      assert {:ok, game, _user} = ZombieAttackContext.report_wave_cleared(scope, game, 1)
      assert game.wave_reached == 1
      assert game.status == "in_progress"
    end

    test "rejects skipping ahead", %{scope: scope} do
      {:ok, game} = ZombieAttackContext.start_zombie_attack_game(scope, 100)

      assert ZombieAttackContext.report_wave_cleared(scope, game, 2) ==
               {:error, :invalid_checkpoint}
    end

    test "rejects repeating the same wave", %{scope: scope} do
      {:ok, game} = ZombieAttackContext.start_zombie_attack_game(scope, 100)
      {:ok, game, _user} = ZombieAttackContext.report_wave_cleared(scope, game, 1)

      assert ZombieAttackContext.report_wave_cleared(scope, game, 1) ==
               {:error, :invalid_checkpoint}
    end

    test "clearing the final wave settles a full-clear win and pays out", %{scope: scope} do
      {:ok, game} = ZombieAttackContext.start_zombie_attack_game(scope, 100)

      game =
        Enum.reduce(1..(ZombieAttack.wave_count() - 1), game, fn wave, game ->
          {:ok, game, _user} = ZombieAttackContext.report_wave_cleared(scope, game, wave)
          game
        end)

      assert {:ok, game, user} =
               ZombieAttackContext.report_wave_cleared(scope, game, ZombieAttack.wave_count())

      assert game.status == "won"
      assert game.payout == ZombieAttack.payout_for(100, :full_clear)

      assert user.tokens_balance ==
               Accounts.zombie_attack_starting_token_amount() - 100 + game.payout
    end
  end

  describe "report_game_over/2" do
    test "settles a loss with zero payout if no wave was cleared", %{scope: scope} do
      {:ok, game} = ZombieAttackContext.start_zombie_attack_game(scope, 100)

      assert {:ok, game, user} = ZombieAttackContext.report_game_over(scope, game)
      assert game.status == "lost"
      assert game.payout == 0
      assert user.tokens_balance == Accounts.zombie_attack_starting_token_amount() - 100
    end

    test "settles a loss with a partial payout based on the highest wave cleared", %{
      scope: scope
    } do
      {:ok, game} = ZombieAttackContext.start_zombie_attack_game(scope, 100)
      {:ok, game, _user} = ZombieAttackContext.report_wave_cleared(scope, game, 1)
      {:ok, game, _user} = ZombieAttackContext.report_wave_cleared(scope, game, 2)

      assert {:ok, game, user} = ZombieAttackContext.report_game_over(scope, game)
      assert game.status == "lost"
      assert game.payout == ZombieAttack.payout_for(100, {:cleared_wave, 2})

      assert user.tokens_balance ==
               Accounts.zombie_attack_starting_token_amount() - 100 + game.payout
    end
  end
end
