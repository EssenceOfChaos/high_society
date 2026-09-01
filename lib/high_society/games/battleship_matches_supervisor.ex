defmodule HighSociety.Games.BattleshipMatchesSupervisor do
  @moduledoc """
  `DynamicSupervisor` for live Battleship matches. Poker's 3 tables are a
  fixed, compile-time list, so a static `Supervisor` always brings all of
  them back on boot; Battleship matches are created ad hoc at runtime and
  should disappear once finished (see `HighSociety.Games.BattleshipMatch`
  stopping itself with reason `:normal` on a win/forfeit), so nothing
  restarts them automatically the way Poker's static children are.
  `rehydrate_in_flight_matches!/0` closes that gap by explicitly
  restarting a process for every match still non-terminal in Postgres.
  """
  use DynamicSupervisor

  import Ecto.Query

  alias HighSociety.Games.BattleshipMatch
  alias HighSociety.Games.BattleshipMatchState
  alias HighSociety.Repo

  @terminal_statuses ~w(player_won opponent_won forfeited cancelled)

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc """
  Starts the match GenServer for `match_config.slug` (its persisted row
  must already exist). `restart: :transient` means a clean `:normal`
  stop (a finished match) is never restarted, but a genuine crash is -
  reloading from Postgres in `BattleshipMatch.init/1`, exactly like a
  Poker table recovering from a crash.
  """
  @spec start_match(%{slug: String.t()}) :: DynamicSupervisor.on_start_child()
  def start_match(match_config) do
    spec = %{
      id: BattleshipMatch,
      start: {BattleshipMatch, :start_link, [match_config]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Starts a process for every match still in a non-terminal state -
  called once at application boot (see `HighSociety.Application`), off
  the main boot path so a slow or failing query never blocks the
  Endpoint from starting.
  """
  @spec rehydrate_in_flight_matches!() :: :ok
  def rehydrate_in_flight_matches! do
    BattleshipMatchState
    |> where([m], m.status not in ^@terminal_statuses)
    |> Repo.all()
    |> Enum.each(&start_match(%{slug: &1.slug}))

    :ok
  end
end
