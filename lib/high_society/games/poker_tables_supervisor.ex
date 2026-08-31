defmodule HighSociety.Games.PokerTablesSupervisor do
  @moduledoc """
  Starts one `HighSociety.Games.PokerTable` GenServer per configured table
  in `HighSociety.Games.PokerTables`. The set of tables is fixed at compile
  time, so this is a plain static supervisor rather than a
  `DynamicSupervisor` - there's never a runtime reason to start or stop a
  table.
  """
  use Supervisor

  alias HighSociety.Games.PokerTable
  alias HighSociety.Games.PokerTables

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children =
      for table_config <- PokerTables.all() do
        Supervisor.child_spec({PokerTable, table_config}, id: {PokerTable, table_config.slug})
      end

    # A generous restart intensity: a table stopping is always intentional
    # (there's no other reason `PokerTable` would ever exit), and the test
    # suite deliberately stops/restarts a table between tests to reset its
    # state (see `HighSociety.PokerFixtures`) many more times, in rapid
    # succession, than the default `max_restarts: 3` in 5 seconds tolerates
    # - which would otherwise take this supervisor down, cascading up to
    # the whole application (`Repo` included, as its sibling).
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 1000, max_seconds: 5)
  end
end
