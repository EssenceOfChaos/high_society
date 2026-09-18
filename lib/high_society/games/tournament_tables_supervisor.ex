defmodule HighSociety.Games.TournamentTablesSupervisor do
  @moduledoc """
  `DynamicSupervisor` for live tournament tables - created ad hoc at
  runtime by `HighSociety.Games.TournamentCoordinator` (initial seating,
  late-join overflow, rebalancing) and closed for good once empty (see
  `HighSociety.Games.TournamentTable`), exactly like
  `HighSociety.Games.BattleshipMatchesSupervisor` does for matches.
  `rehydrate_in_flight_tables!/0` restarts a process for every table still
  `active` in Postgres.

  Registered under the shared `HighSociety.Games.TournamentRegistry`
  (tagged `{:table, slug}` - see `TournamentTable.via/1`), alongside
  `HighSociety.Games.TournamentsSupervisor`'s coordinators (tagged
  `{:coordinator, tournament_id}`), rather than a second dedicated
  registry - one fewer named process for no loss, since the tags already
  keep the two kinds of key apart.
  """
  use DynamicSupervisor

  import Ecto.Query

  alias HighSociety.Games.TournamentTable
  alias HighSociety.Games.TournamentTableState
  alias HighSociety.Repo

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc """
  Starts the table GenServer for `table_config` (`%{slug, tournament_id}`;
  its persisted row must already exist - see `TournamentTable.create!/2`).
  `restart: :transient` means a clean `:normal` stop (a table that closed
  because it emptied out) is never restarted, but a genuine crash is -
  reloading from Postgres in `TournamentTable.init/1`.
  """
  @spec start_table(%{slug: String.t(), tournament_id: pos_integer()}) ::
          DynamicSupervisor.on_start_child()
  def start_table(table_config) do
    spec = %{
      id: TournamentTable,
      start: {TournamentTable, :start_link, [table_config]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @doc """
  Starts a process for every table still `active` - called once at
  application boot (see `HighSociety.Application`), off the main boot
  path (a detached, unlinked `Task`) so a slow or failing query never
  blocks the Endpoint from starting, and so a boot-time
  `DBConnection.OwnershipError` in the test environment (no sandbox
  checked out yet - see `HighSociety.Games.PokerTable.load_row/1`'s
  identical situation) just quietly kills this one Task rather than
  crashing the app, exactly like
  `HighSociety.Games.BattleshipMatchesSupervisor.rehydrate_in_flight_matches!/0`.
  """
  @spec rehydrate_in_flight_tables!() :: :ok
  def rehydrate_in_flight_tables! do
    TournamentTableState
    |> where([t], t.status == "active")
    |> Repo.all()
    |> Enum.each(&start_table(%{slug: &1.slug, tournament_id: &1.tournament_id}))

    :ok
  end
end
