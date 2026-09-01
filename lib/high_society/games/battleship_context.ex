defmodule HighSociety.Games.BattleshipContext do
  @moduledoc """
  Persistence and wagering for vs-computer Battleship. A dedicated
  module (rather than folding into `HighSociety.Games`, which stays
  scoped to War/Blackjack's single-player-vs-house shape) since
  Battleship's two-fleet, two-shot-grid state and AI turn resolution are
  a meaningfully larger surface than either of those.

  The computer's turn is resolved synchronously, in the same call as the
  player's shot, rather than paced with a `Process.send_after` the way
  Blackjack paces the dealer's play-out. Blackjack's dealer draws a
  variable-length sequence of cards worth revealing one at a time; a
  computer Battleship turn is one atomic shot, so there's nothing to
  stage - and resolving both shots in one request/DB write means there's
  never a "half a turn" state if the player navigates away mid-turn. Any
  dramatic pause before showing the computer's (already-decided) shot is
  a LiveView-side animation concern, not a game-state one.
  """

  import Ecto.Query, warn: false

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Accounts.User
  alias HighSociety.Games.Battleship
  alias HighSociety.Games.BattleshipAI
  alias HighSociety.Games.BattleshipGame
  alias HighSociety.Repo

  @unresolved_statuses ~w(placing_fleets player_turn opponent_turn)

  @doc "The current user's in-progress Battleship game, or `nil`."
  @spec get_active_battleship_game(Scope.t()) :: BattleshipGame.t() | nil
  def get_active_battleship_game(%Scope{user: user}) do
    Repo.one(
      from bg in BattleshipGame,
        where: bg.user_id == ^user.id and bg.status in ^@unresolved_statuses
    )
  end

  @doc """
  Starts a fresh vs-computer game, debiting `wager` from the user's
  balance up front. Discards any previous unresolved game for the user.
  The computer's fleet is placed (and readied) immediately via
  `Battleship.random_fleet/0`; the player's fleet starts empty, ready
  for manual placement.
  """
  @spec start_battleship_game(Scope.t(), pos_integer) ::
          {:ok, BattleshipGame.t()} | {:error, :insufficient_funds}
  def start_battleship_game(%Scope{user: user}, wager) when is_integer(wager) and wager > 0 do
    Repo.transact(fn ->
      with {:ok, _user} <- Accounts.adjust_balance(user, -wager) do
        Repo.delete_all(
          from bg in BattleshipGame,
            where: bg.user_id == ^user.id and bg.status in ^@unresolved_statuses
        )

        battleship = %Battleship{opponent_fleet: Battleship.random_fleet()}
        {:ok, battleship} = Battleship.ready_up(battleship, :opponent)

        {:ok, save(%BattleshipGame{user_id: user.id, wager: wager}, battleship)}
      end
    end)
  end

  @doc "Replaces the player's fleet with a fresh random placement. Backs the \"randomize\" button."
  @spec randomize_player_fleet(BattleshipGame.t()) :: BattleshipGame.t()
  def randomize_player_fleet(%BattleshipGame{} = game) do
    battleship = to_battleship(game) |> Map.put(:player_fleet, Battleship.random_fleet())
    save(game, battleship)
  end

  @doc "Empties the player's fleet so they can start placement over. Backs the \"clear\" button."
  @spec clear_player_fleet(BattleshipGame.t()) :: BattleshipGame.t()
  def clear_player_fleet(%BattleshipGame{} = game) do
    battleship = %{to_battleship(game) | player_fleet: []}
    save(game, battleship)
  end

  @doc "Places one ship in the player's fleet. See `Battleship.place_ship/4`."
  @spec place_ship(BattleshipGame.t(), atom, Battleship.coord(), Battleship.orientation()) ::
          {:ok, BattleshipGame.t()} | {:error, atom}
  def place_ship(%BattleshipGame{} = game, ship_type, coord, orientation) do
    battleship = to_battleship(game)

    case Battleship.place_ship(battleship.player_fleet, ship_type, coord, orientation) do
      {:ok, fleet} -> {:ok, save(game, %{battleship | player_fleet: fleet})}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Locks in the player's fleet. Since the computer's side is already
  readied at creation, this is what actually starts the match - and
  since `Battleship.ready_up/2` coin-flips who goes first, this also
  immediately resolves the computer's opening shot on the (roughly
  50% of the time) chance it won that flip. Without this, a game that
  started on `:opponent_turn` would simply stall forever: unlike the
  live vs-human mode, there's no separate connected process representing
  the computer that could otherwise take its turn.
  """
  @spec ready_up_player(BattleshipGame.t()) :: {:ok, BattleshipGame.t()} | {:error, :fleet_incomplete}
  def ready_up_player(%BattleshipGame{} = game) do
    case Battleship.ready_up(to_battleship(game), :player) do
      {:ok, battleship} ->
        {battleship, _computer_result} = maybe_computer_fire(battleship)
        {:ok, save(game, battleship)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resolves the player firing at `coord` and, if the game isn't over,
  immediately also resolves the computer's return shot. Settles the
  wager once the game ends: a win pays `wager * 2`; a loss keeps the
  up-front debit as-is. Returns the updated game alongside the (possibly
  credited) user.
  """
  @spec fire(Scope.t(), BattleshipGame.t(), Battleship.coord()) ::
          {:ok, BattleshipGame.t(), User.t(), %{player: map, computer: map | nil}} | {:error, atom}
  def fire(%Scope{user: user}, %BattleshipGame{} = game, coord) do
    battleship = to_battleship(game)

    with {:ok, player_result, battleship} <- Battleship.fire(battleship, :player, coord) do
      {battleship, computer_result} = maybe_computer_fire(battleship)
      payout = payout_for(battleship, game.wager)

      {:ok, user} =
        if payout > 0, do: Accounts.adjust_balance(user, payout), else: {:ok, user}

      game = save(game, battleship, %{payout: (payout > 0 && payout) || game.payout})
      {:ok, game, user, %{player: player_result, computer: computer_result}}
    end
  end

  defp maybe_computer_fire(%Battleship{status: :opponent_turn} = battleship) do
    coord = BattleshipAI.choose_shot(ai_shots_fired(battleship), ai_sunk_ship_cells(battleship))
    {:ok, result, battleship} = Battleship.fire(battleship, :opponent, coord)
    {battleship, Map.put(result, :coord, coord)}
  end

  defp maybe_computer_fire(battleship), do: {battleship, nil}

  # The AI's own view of the board: the shots it's fired (with results)
  # and which of the player's ships are already fully sunk, both in the
  # tuple-coord/atom-result shape `BattleshipAI` expects rather than the
  # string-keyed jsonb shape `Battleship` persists.
  defp ai_shots_fired(%Battleship{opponent_shots: shots}) do
    Map.new(shots, fn {coord_str, result} ->
      {:ok, coord} = Battleship.parse_coord(coord_str)
      {coord, if(result == "miss", do: :miss, else: :hit)}
    end)
  end

  defp ai_sunk_ship_cells(%Battleship{player_fleet: fleet}) do
    fleet
    |> Enum.filter(&(MapSet.size(&1.hits) == length(&1.cells)))
    |> Enum.flat_map(& &1.cells)
  end

  defp payout_for(%Battleship{status: :player_won}, wager), do: wager * 2
  defp payout_for(_battleship, _wager), do: 0

  defp to_battleship(%BattleshipGame{battleship: battleship}), do: Battleship.from_json(battleship)

  defp save(%BattleshipGame{} = game, %Battleship{} = battleship, extra_attrs \\ %{}) do
    attrs =
      Map.merge(
        %{status: Atom.to_string(battleship.status), battleship: Battleship.to_json(battleship)},
        extra_attrs
      )

    game
    |> BattleshipGame.changeset(attrs)
    |> Repo.insert_or_update!()
  end
end
