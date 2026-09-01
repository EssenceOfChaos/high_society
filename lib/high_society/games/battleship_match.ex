defmodule HighSociety.Games.BattleshipMatch do
  @moduledoc """
  One GenServer per live 2-player Battleship match, registered under
  `HighSociety.Games.BattleshipRegistry` by slug - mirrors
  `HighSociety.Games.PokerTable`'s shape: every mutating call is
  serialized through this single process, and every change is persisted
  to a `HighSociety.Games.BattleshipMatchState` row before being
  broadcast, so a crash or deploy never loses either seat's stake.

  Internally, seat 0 is always `:player` and seat 1 is always `:opponent`
  in `HighSociety.Games.Battleship` terms - `public_view/2` presents this
  one canonical view to both connected LiveViews, which each adapt it to
  "me" vs. "opponent" based on which seat their own user occupies.

  Unlike a Poker table, a match should not live forever: once it ends
  (a win or an explicit forfeit), the final state is persisted and
  broadcast, and then this process stops itself with reason `:normal` -
  `HighSociety.Games.BattleshipMatchesSupervisor`'s `restart: :transient`
  child spec means that's respected, while a genuine crash still gets
  restarted and reloads from Postgres.
  """
  use GenServer

  import Ecto.Query

  alias HighSociety.Accounts
  alias HighSociety.Accounts.User
  alias HighSociety.Games.Battleship
  alias HighSociety.Games.BattleshipMatches
  alias HighSociety.Games.BattleshipMatchesSupervisor
  alias HighSociety.Games.BattleshipMatchState
  alias HighSociety.Repo

  @terminal_statuses [:player_won, :opponent_won, :forfeited, :cancelled]

  ## Public API

  def start_link(match_config),
    do: GenServer.start_link(__MODULE__, match_config, name: via(match_config.slug))

  def via(slug), do: {:via, Registry, {HighSociety.Games.BattleshipRegistry, slug}}

  @doc "The PubSub topic a match's updates are broadcast on."
  def topic(slug), do: "battleship_match:#{slug}"

  @doc """
  Creates a new match: debits `wager` from `user`'s balance, persists a
  fresh `waiting_for_opponent` row, and starts its GenServer. Returns the
  new match's slug.
  """
  @spec create(User.t(), pos_integer) :: {:ok, String.t()} | {:error, :insufficient_funds}
  def create(%User{} = user, wager) when is_integer(wager) and wager > 0 do
    result =
      Repo.transact(fn ->
        with {:ok, _user} <- Accounts.adjust_balance(user, -wager) do
          slug = generate_unique_slug()

          %BattleshipMatchState{}
          |> BattleshipMatchState.changeset(%{
            slug: slug,
            wager: wager,
            status: "waiting_for_opponent",
            seat_0_user_id: user.id
          })
          |> Repo.insert!()

          {:ok, slug}
        end
      end)

    with {:ok, slug} <- result do
      {:ok, _pid} = BattleshipMatchesSupervisor.start_match(%{slug: slug})
      {:ok, slug}
    end
  end

  @doc "Seats `user` in the open second seat, debiting the matching wager."
  def join(slug, %User{} = user), do: GenServer.call(via(slug), {:join, user})

  @doc "Places one ship in `user_id`'s fleet during placement. See `Battleship.place_ship/4`."
  def place_ship(slug, user_id, ship_type, coord, orientation),
    do: GenServer.call(via(slug), {:place_ship, user_id, ship_type, coord, orientation})

  @doc "Replaces `user_id`'s fleet with a fresh random placement."
  def randomize_fleet(slug, user_id), do: GenServer.call(via(slug), {:randomize_fleet, user_id})

  @doc "Empties `user_id`'s fleet so they can start placement over."
  def clear_fleet(slug, user_id), do: GenServer.call(via(slug), {:clear_fleet, user_id})

  @doc "Locks in `user_id`'s fleet. Starts the match once both seats are ready."
  def ready_up(slug, user_id), do: GenServer.call(via(slug), {:ready_up, user_id})

  @doc "Fires at `coord` on behalf of `user_id`. See `Battleship.fire/3`."
  def fire(slug, user_id, coord), do: GenServer.call(via(slug), {:fire, user_id, coord})

  @doc "Concedes the match on behalf of `user_id`; the other seat takes the whole pot."
  def forfeit(slug, user_id), do: GenServer.call(via(slug), {:forfeit, user_id})

  @doc """
  Cancels a match that's still waiting for an opponent, refunding the
  creator's wager. Only the creator (seat 0) can cancel, and only before
  anyone has joined - once a second player is seated, both sides have a
  stake in the outcome, so `forfeit/2` is the appropriate way out instead.
  """
  def cancel(slug, user_id), do: GenServer.call(via(slug), {:cancel, user_id})

  @doc "The match's current public state."
  def get_state(slug), do: GenServer.call(via(slug), :get_state)

  ## Callbacks

  @impl true
  def init(%{slug: slug}) do
    # See `HighSociety.Games.PokerTable.init/1` for why: a match restarted
    # by the DynamicSupervisor after a crash, or rehydrated at boot, can
    # deserialize a persisted `Battleship` before anything else has
    # loaded that module - `String.to_existing_atom/1` inside
    # `Battleship.from_json/1` needs its atoms already interned.
    Code.ensure_loaded!(Battleship)
    row = Repo.get_by!(BattleshipMatchState, slug: slug)
    {:ok, from_row(row)}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, public_view(state), state}

  def handle_call({:join, user}, _from, state) do
    cond do
      state.seat_1_user_id != nil ->
        {:reply, {:error, :match_full}, state}

      state.seat_0_user_id == user.id ->
        {:reply, {:error, :already_seated}, state}

      true ->
        case Accounts.adjust_balance(user, -state.wager) do
          {:ok, _user} ->
            state = %{
              state
              | seat_1_user_id: user.id,
                seat_1_username: username(user),
                battleship: %Battleship{},
                status: :placing_fleets
            }

            finalize(state)

          {:error, :insufficient_funds} ->
            {:reply, {:error, :insufficient_funds}, state}
        end
    end
  end

  def handle_call({:place_ship, user_id, ship_type, coord, orientation}, _from, state) do
    with_seat(state, user_id, fn side ->
      fleet = Map.fetch!(state.battleship, fleet_field(side))

      case Battleship.place_ship(fleet, ship_type, coord, orientation) do
        {:ok, fleet} ->
          battleship = Map.put(state.battleship, fleet_field(side), fleet)
          finalize(%{state | battleship: battleship})

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end)
  end

  def handle_call({:randomize_fleet, user_id}, _from, state) do
    with_seat(state, user_id, fn side ->
      battleship = Map.put(state.battleship, fleet_field(side), Battleship.random_fleet())
      finalize(%{state | battleship: battleship})
    end)
  end

  def handle_call({:clear_fleet, user_id}, _from, state) do
    with_seat(state, user_id, fn side ->
      battleship = Map.put(state.battleship, fleet_field(side), [])
      finalize(%{state | battleship: battleship})
    end)
  end

  def handle_call({:ready_up, user_id}, _from, state) do
    with_seat(state, user_id, fn side ->
      case Battleship.ready_up(state.battleship, side) do
        {:ok, battleship} -> finalize(%{state | battleship: battleship, status: battleship.status})
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end)
  end

  def handle_call({:fire, user_id, coord}, _from, state) do
    with_seat(state, user_id, fn side ->
      case Battleship.fire(state.battleship, side, coord) do
        {:ok, result, battleship} ->
          last_shot = %{side: side, coord: Battleship.format_coord(coord), result: result}

          %{state | battleship: battleship, status: battleship.status}
          |> settle_if_won()
          |> finalize(last_shot)

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end)
  end

  def handle_call({:forfeit, user_id}, _from, state) do
    with_seat(state, user_id, fn side ->
      winner_user_id = if side == :player, do: state.seat_1_user_id, else: state.seat_0_user_id
      {:ok, _user} = Accounts.adjust_balance(Accounts.get_user!(winner_user_id), state.wager * 2)

      finalize(%{state | status: :forfeited})
    end)
  end

  # Not routed through `with_seat/3`: that helper requires `state.battleship`
  # to already exist, which it doesn't yet while still `:waiting_for_opponent`
  # (see `handle_call({:join, ...})` - `battleship` is only set once a second
  # seat fills). Cancelling only makes sense in exactly that pre-join window.
  def handle_call({:cancel, user_id}, _from, state) do
    cond do
      state.status != :waiting_for_opponent ->
        {:reply, {:error, :already_started}, state}

      state.seat_0_user_id != user_id ->
        {:reply, {:error, :not_seated}, state}

      true ->
        {:ok, _user} = Accounts.adjust_balance(Accounts.get_user!(state.seat_0_user_id), state.wager)
        finalize(%{state | status: :cancelled})
    end
  end

  ## Seat lookup

  defp with_seat(state, user_id, fun) do
    case seat_for_user(state, user_id) do
      nil -> {:reply, {:error, :not_seated}, state}
      _side when is_nil(state.battleship) -> {:reply, {:error, :not_started}, state}
      side -> fun.(side)
    end
  end

  defp seat_for_user(%{seat_0_user_id: id}, user_id) when id == user_id, do: :player
  defp seat_for_user(%{seat_1_user_id: id}, user_id) when id == user_id, do: :opponent
  defp seat_for_user(_state, _user_id), do: nil

  defp fleet_field(:player), do: :player_fleet
  defp fleet_field(:opponent), do: :opponent_fleet

  defp username(user), do: user.email |> String.split("@") |> hd()

  ## Settling a win

  defp settle_if_won(%{status: :player_won} = state), do: credit_winner(state, state.seat_0_user_id)
  defp settle_if_won(%{status: :opponent_won} = state), do: credit_winner(state, state.seat_1_user_id)
  defp settle_if_won(state), do: state

  defp credit_winner(state, winner_user_id) do
    {:ok, _user} = Accounts.adjust_balance(Accounts.get_user!(winner_user_id), state.wager * 2)
    state
  end

  ## Persistence + broadcast

  defp finalize(state, last_shot \\ nil) do
    persist(state)
    broadcast(state, last_shot)
    reply = {:ok, public_view(state, last_shot)}

    if state.status in @terminal_statuses,
      do: {:stop, :normal, reply, state},
      else: {:reply, reply, state}
  end

  defp persist(state) do
    now = DateTime.utc_now(:second)

    %BattleshipMatchState{}
    |> BattleshipMatchState.changeset(%{
      slug: state.slug,
      wager: state.wager,
      status: Atom.to_string(state.status),
      seat_0_user_id: state.seat_0_user_id,
      seat_1_user_id: state.seat_1_user_id,
      battleship: state.battleship && Battleship.to_json(state.battleship)
    })
    |> Ecto.Changeset.put_change(:inserted_at, now)
    |> Ecto.Changeset.put_change(:updated_at, now)
    |> Repo.insert!(
      on_conflict:
        {:replace, [:wager, :status, :seat_0_user_id, :seat_1_user_id, :battleship, :updated_at]},
      conflict_target: :slug
    )
  end

  defp broadcast(state, last_shot) do
    Phoenix.PubSub.broadcast(
      HighSociety.PubSub,
      topic(state.slug),
      {:battleship_match_updated, public_view(state, last_shot)}
    )

    Phoenix.PubSub.broadcast(
      HighSociety.PubSub,
      BattleshipMatches.topic(),
      {:battleship_lobby_updated, lobby_entry(state)}
    )
  end

  defp lobby_entry(state) do
    %{
      slug: state.slug,
      wager: state.wager,
      status: Atom.to_string(state.status),
      seat_count: Enum.count([state.seat_0_user_id, state.seat_1_user_id], & &1)
    }
  end

  defp public_view(state, last_shot \\ nil) do
    %{
      slug: state.slug,
      wager: state.wager,
      status: state.status,
      seats: %{
        0 => state.seat_0_user_id && %{user_id: state.seat_0_user_id, username: state.seat_0_username},
        1 => state.seat_1_user_id && %{user_id: state.seat_1_user_id, username: state.seat_1_username}
      },
      battleship: state.battleship,
      last_shot: last_shot
    }
  end

  ## Loading

  defp from_row(row) do
    %{
      slug: row.slug,
      wager: row.wager,
      seat_0_user_id: row.seat_0_user_id,
      seat_1_user_id: row.seat_1_user_id,
      seat_0_username: row.seat_0_user_id && username(Accounts.get_user!(row.seat_0_user_id)),
      seat_1_username: row.seat_1_user_id && username(Accounts.get_user!(row.seat_1_user_id)),
      battleship: row.battleship && Battleship.from_json(row.battleship),
      status: status_atom(row.status)
    }
  end

  # Explicit, rather than `String.to_existing_atom/1`: `:waiting_for_opponent`
  # (a match-lifecycle status with no equivalent in `Battleship` itself,
  # unlike the others) is never written as an atom literal anywhere in this
  # module's own code, only ever persisted as a string - so relying on it
  # having been interned by *something* elsewhere would be a real crash on
  # a match's very first load after a fresh boot, not just a rare race.
  defp status_atom("waiting_for_opponent"), do: :waiting_for_opponent
  defp status_atom("placing_fleets"), do: :placing_fleets
  defp status_atom("player_turn"), do: :player_turn
  defp status_atom("opponent_turn"), do: :opponent_turn
  defp status_atom("player_won"), do: :player_won
  defp status_atom("opponent_won"), do: :opponent_won
  defp status_atom("forfeited"), do: :forfeited
  defp status_atom("cancelled"), do: :cancelled

  defp generate_unique_slug do
    slug = :crypto.strong_rand_bytes(4) |> Base.encode32(case: :lower, padding: false)

    if Repo.exists?(from m in BattleshipMatchState, where: m.slug == ^slug),
      do: generate_unique_slug(),
      else: slug
  end
end
