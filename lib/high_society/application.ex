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
      # Start to serve requests, typically the last entry
      HighSocietyWeb.Endpoint
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
