defmodule HighSociety.Games.BattleshipContextTest do
  use HighSociety.DataCase, async: true

  alias HighSociety.Accounts
  alias HighSociety.Games.Battleship
  alias HighSociety.Games.BattleshipContext

  import HighSociety.AccountsFixtures

  setup do
    {:ok, user} = user_scope_fixture().user |> Accounts.claim_starting_chips()
    %{scope: user_scope_fixture(user)}
  end

  defp force_status(game, status) do
    battleship = %{Battleship.from_json(game.battleship) | status: status}
    %{game | status: Atom.to_string(status), battleship: Battleship.to_json(battleship)}
  end

  describe "start_battleship_game/2" do
    test "debits the wager and readies the computer's fleet", %{scope: scope} do
      assert {:ok, game} = BattleshipContext.start_battleship_game(scope, 100)

      assert game.user_id == scope.user.id
      assert game.wager == 100
      assert game.status == "placing_fleets"

      battleship = Battleship.from_json(game.battleship)
      assert battleship.opponent_ready?
      assert Battleship.fleet_complete?(battleship.opponent_fleet)
      assert battleship.player_fleet == []

      assert Accounts.get_user!(scope.user.id).balance == Accounts.starting_chip_amount() - 100
    end

    test "rejects a wager the user can't afford" do
      scope = user_scope_fixture()
      assert BattleshipContext.start_battleship_game(scope, 100) == {:error, :insufficient_funds}
    end

    test "discards any previous unresolved game for the user", %{scope: scope} do
      {:ok, first} = BattleshipContext.start_battleship_game(scope, 50)
      {:ok, second} = BattleshipContext.start_battleship_game(scope, 50)

      assert first.id != second.id
      refute HighSociety.Repo.get(HighSociety.Games.BattleshipGame, first.id)
    end
  end

  describe "get_active_battleship_game/1" do
    test "returns nil with no game", %{scope: scope} do
      assert BattleshipContext.get_active_battleship_game(scope) == nil
    end

    test "returns the user's unresolved game", %{scope: scope} do
      {:ok, game} = BattleshipContext.start_battleship_game(scope, 50)
      assert BattleshipContext.get_active_battleship_game(scope).id == game.id
    end
  end

  describe "placement" do
    setup %{scope: scope} do
      {:ok, game} = BattleshipContext.start_battleship_game(scope, 50)
      %{game: game}
    end

    test "place_ship/4 places one ship", %{game: game} do
      assert {:ok, game} = BattleshipContext.place_ship(game, :destroyer, {0, 0}, :horizontal)
      battleship = Battleship.from_json(game.battleship)
      assert [%{type: :destroyer}] = battleship.player_fleet
    end

    test "place_ship/4 rejects an invalid placement", %{game: game} do
      assert BattleshipContext.place_ship(game, :carrier, {9, 0}, :horizontal) ==
               {:error, :out_of_bounds}
    end

    test "randomize_player_fleet/1 produces a complete fleet", %{game: game} do
      game = BattleshipContext.randomize_player_fleet(game)
      battleship = Battleship.from_json(game.battleship)
      assert Battleship.fleet_complete?(battleship.player_fleet)
    end

    test "clear_player_fleet/1 empties a fully or partially placed fleet", %{game: game} do
      game = BattleshipContext.randomize_player_fleet(game)
      game = BattleshipContext.clear_player_fleet(game)
      battleship = Battleship.from_json(game.battleship)
      assert battleship.player_fleet == []
    end

    test "ready_up_player/1 rejects an incomplete fleet", %{game: game} do
      assert BattleshipContext.ready_up_player(game) == {:error, :fleet_incomplete}
    end

    test "ready_up_player/1 starts the match once the player's fleet is complete", %{game: game} do
      game = BattleshipContext.randomize_player_fleet(game)
      assert {:ok, game} = BattleshipContext.ready_up_player(game)
      assert game.status in ["player_turn", "opponent_turn"]
    end
  end

  describe "fire/3" do
    setup %{scope: scope} do
      {:ok, game} = BattleshipContext.start_battleship_game(scope, 50)
      game = BattleshipContext.randomize_player_fleet(game)
      {:ok, game} = BattleshipContext.ready_up_player(game)
      %{game: force_status(game, :player_turn)}
    end

    test "resolves the player's shot and, if the game continues, the computer's return shot",
         %{scope: scope, game: game} do
      assert {:ok, game, _user, results} = BattleshipContext.fire(scope, game, {0, 0})
      assert results.player.result in [:hit, :miss, :sunk]

      updated = Battleship.from_json(game.battleship)

      if updated.status in [:player_turn, :opponent_turn] do
        assert results.computer != nil
        # At least this shot - possibly a second, if the computer also won
        # the coin flip to open the match (see `ready_up_player/1`).
        assert map_size(updated.opponent_shots) >= 1
      end
    end

    test "rejects re-firing at an already-shot cell", %{scope: scope, game: game} do
      {:ok, game, _user, _results} = BattleshipContext.fire(scope, game, {0, 0})
      game = force_status(game, :player_turn)
      assert BattleshipContext.fire(scope, game, {0, 0}) == {:error, :already_shot}
    end

    test "credits 2x the wager to the user on a win", %{scope: scope, game: game} do
      # Force a deterministic win: give the computer a fleet of five
      # single-cell "ships" at known coordinates, so 5 shots always sinks
      # the whole fleet regardless of the real ship-length rules (which
      # only `place_ship/4` enforces, not `fire/3`).
      battleship = Battleship.from_json(game.battleship)

      opponent_fleet =
        for {type, coord} <- [
              carrier: {0, 0},
              battleship: {9, 9},
              cruiser: {9, 8},
              submarine: {9, 7},
              destroyer: {9, 6}
            ] do
          %{type: type, cells: [coord], hits: MapSet.new()}
        end

      game =
        game
        |> Map.replace!(:battleship, Battleship.to_json(%{battleship | opponent_fleet: opponent_fleet}))
        |> force_status(:player_turn)

      balance_before = Accounts.get_user!(scope.user.id).balance

      final =
        Enum.reduce([{0, 0}, {9, 9}, {9, 8}, {9, 7}, {9, 6}], game, fn coord, game ->
          {:ok, game, _user, _results} = BattleshipContext.fire(scope, game, coord)
          game
        end)

      assert final.status == "player_won"
      assert final.payout == 100
      assert Accounts.get_user!(scope.user.id).balance == balance_before + 100
    end
  end
end
