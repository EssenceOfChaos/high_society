defmodule HighSociety.Games.TournamentsSupervisor do
  @moduledoc """
  `DynamicSupervisor` for tournament coordinators - one per running
  tournament, started only when an admin manually starts a tournament
  (`HighSociety.Tournaments.start!/1`) or rehydrated after a crash/deploy
  for every tournament still `running` in Postgres. A separate supervision
  root from `HighSociety.Games.TournamentTablesSupervisor` (not nested
  under it), sharing only the `TournamentRegistry` name, so table
  rehydration can run first and independently - see
  `rehydrate_in_flight_tournaments!/0` and `HighSociety.Application`'s
  boot ordering, which starts this sweep only after the table sweep.
  """
  use DynamicSupervisor

  import Ecto.Query

  alias HighSociety.Games.TournamentCoordinator
  alias HighSociety.Repo
  alias HighSociety.Tournaments.PokerTournament

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc """
  Starts the coordinator for `tournament_id` (its `poker_tournaments` row
  must already exist and be `running`). `restart: :transient` means a
  clean `:normal` stop is never restarted, but a genuine crash is -
  reloading from Postgres in `TournamentCoordinator.init/1`.
  """
  @spec start_coordinator(pos_integer()) :: DynamicSupervisor.on_start_child()
  def start_coordinator(tournament_id) do
    spec = %{
      id: TournamentCoordinator,
      start: {TournamentCoordinator, :start_link, [%{tournament_id: tournament_id}]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @doc """
  Starts a coordinator for every tournament still `running` - called once
  at application boot (see `HighSociety.Application`), off the main boot
  path (a detached, unlinked `Task`) for the same reasons as
  `HighSociety.Games.TournamentTablesSupervisor.rehydrate_in_flight_tables!/0`,
  and always scheduled *after* that sweep so every table a coordinator
  might look up in `init/1` is already back up.
  """
  @spec rehydrate_in_flight_tournaments!() :: :ok
  def rehydrate_in_flight_tournaments! do
    PokerTournament
    |> where([t], t.status == "running")
    |> Repo.all()
    |> Enum.each(&start_coordinator(&1.id))

    :ok
  end
end
