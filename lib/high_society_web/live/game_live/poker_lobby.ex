defmodule HighSocietyWeb.GameLive.PokerLobby do
  use HighSocietyWeb, :live_view

  alias HighSociety.Games.PokerTable
  alias HighSociety.Games.PokerTables

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Enum.each(
        PokerTables.all(),
        &Phoenix.PubSub.subscribe(HighSociety.PubSub, PokerTable.topic(&1.slug))
      )
    end

    tables =
      PokerTables.all()
      |> Enum.map(fn table_config ->
        state =
          if connected?(socket), do: PokerTable.get_state(table_config.slug), else: %{seats: %{}}

        {table_config.slug, %{config: table_config, seats: state.seats}}
      end)
      |> Map.new()

    {:ok, assign(socket, :tables, tables)}
  end

  @impl true
  def handle_info({:poker_table_updated, view}, socket) do
    tables = Map.update!(socket.assigns.tables, view.slug, &%{&1 | seats: view.seats})
    {:noreply, assign(socket, :tables, tables)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl">
        <.link navigate={~p"/"} class="text-sm text-base-content/60 hover:text-base-content">
          &larr; All games
        </.link>
        <h1 class="mt-1 text-3xl font-bold tracking-tight">Poker</h1>
        <p class="mt-2 text-base-content/70">
          No-Limit Texas Hold'em cash games. Pick a table to watch, or sit down when a seat opens up.
        </p>

        <div class="mt-8 grid grid-cols-1 gap-6 sm:grid-cols-3">
          <.link
            :for={{slug, table} <- Enum.sort_by(@tables, fn {_slug, t} -> t.config.big_blind end)}
            navigate={~p"/games/poker/#{slug}"}
            id={"poker-table-#{slug}"}
            class="group relative flex flex-col rounded-box border border-base-300 bg-base-100 p-6 shadow-sm transition-all duration-300 hover:-translate-y-1 hover:shadow-lg"
          >
            <h2 class="text-2xl font-semibold">{table.config.name}</h2>
            <p class="text-sm font-medium text-base-content/50">
              Blinds ${table.config.small_blind} / ${table.config.big_blind}
            </p>
            <div class="mt-4 flex items-center gap-2 text-sm">
              <span class="flex items-center gap-1.5 rounded-full bg-base-200 px-3 py-1 font-semibold">
                <.icon name="hero-user-group" class="size-4" />
                {map_size(table.seats)} / {PokerTables.seats()} seated
              </span>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
