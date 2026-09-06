defmodule HighSociety.Healthcheck.Supervisor do
  alias HighSociety.Healthcheck.Worker

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children =
      :high_society
      |> Application.get_env(:healthcheck, [])
      |> Keyword.get(:services, [])
      |> Enum.map(fn {service, opts} ->
        refresh_interval = Keyword.fetch!(opts, :refresh_interval)
        Supervisor.child_spec({Worker, [service, refresh_interval]}, id: service)
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
