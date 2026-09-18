defmodule HighSociety.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if Application.get_env(:high_society, :run_migrations_on_boot, false) do
      HighSociety.Release.migrate()
    end

    children = [
      HighSocietyWeb.Telemetry,
      HighSociety.Repo,
      {DNSCluster, query: Application.get_env(:high_society, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: HighSociety.PubSub},
      HighSocietyWeb.Presence,
      {Registry, keys: :unique, name: HighSociety.Games.PokerRegistry},
      HighSociety.Games.PokerTablesSupervisor,
      {Registry, keys: :unique, name: HighSociety.Games.BattleshipRegistry},
      HighSociety.Games.BattleshipMatchesSupervisor,
      # Shared by both tournament tables (tagged `{:table, slug}`) and
      # tournament coordinators (tagged `{:coordinator, tournament_id}`) -
      # see `HighSociety.Games.TournamentTablesSupervisor`'s moduledoc.
      {Registry, keys: :unique, name: HighSociety.Games.TournamentRegistry},
      HighSociety.Games.TournamentTablesSupervisor,
      HighSociety.Games.TournamentsSupervisor,
      # Start to serve requests, typically the last entry
      HighSocietyWeb.Endpoint,
      HighSociety.Healthcheck.Supervisor
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HighSociety.Supervisor]

    with {:ok, _pid} = ok <- Supervisor.start_link(children, opts) do
      # Dev-only (see `HighSociety.Games.PokerBots`): seat the two bot
      # accounts once everything, including the poker tables, is up. Run
      # off a separate process since seating calls back into a table
      # GenServer that's a sibling in this same tree, not an ancestor.
      if HighSociety.Games.PokerBots.enabled?(),
        do: Task.start(&HighSociety.Games.PokerBots.maintain!/0)

      # Unlike Poker's fixed tables, a dynamically-supervised Battleship
      # match isn't restarted automatically by the supervision tree - see
      # `HighSociety.Games.BattleshipMatchesSupervisor`. Off a separate
      # process for the same non-blocking-boot reason as the bot seeding
      # above.
      Task.start(&HighSociety.Games.BattleshipMatchesSupervisor.rehydrate_in_flight_matches!/0)

      # Tables rehydrate independently of, and before, any tournament
      # coordinator - each table's own `init/1` is fully self-contained,
      # with no dependency on its coordinator being alive. Coordinators
      # rehydrate second so every table a coordinator looks up already
      # exists; each `Task.start/1` is unlinked, so either query failing
      # at boot (e.g. the test-sandbox-ownership race described in
      # `HighSociety.Games.PokerTable.load_row/1`) just quietly kills
      # that one Task rather than the app, exactly like
      # `BattleshipMatchesSupervisor.rehydrate_in_flight_matches!/0`.
      Task.start(fn ->
        HighSociety.Games.TournamentTablesSupervisor.rehydrate_in_flight_tables!()
        HighSociety.Games.TournamentsSupervisor.rehydrate_in_flight_tournaments!()
      end)

      ok
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HighSocietyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
