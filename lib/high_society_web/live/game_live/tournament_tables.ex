defmodule HighSocietyWeb.GameLive.TournamentTables do
  @moduledoc """
  "Pick a table to watch" for a running tournament - modeled on
  `HighSocietyWeb.GameLive.BattleshipLobby`, but sourced from
  `HighSociety.Games.TournamentCoordinator`'s own live state (which it
  already tracks and broadcasts) rather than a fresh DB query per update,
  since the coordinator is the one process that always knows exactly
  which tables are active and who's on them.
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Games.TournamentCoordinator
  alias HighSociety.Tokens
  alias HighSociety.Tournaments

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    tournament = Tournaments.get_tournament!(id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(HighSociety.PubSub, TournamentCoordinator.topic(tournament.id))
    end

    socket =
      socket
      |> assign(:page_title, "#{tournament.name} – Tables")
      |> assign(:tournament, tournament)
      |> assign(coordinator_assigns(tournament.id))

    {:ok, socket}
  end

  @impl true
  def handle_info({:tournament_updated, view}, socket) do
    {:noreply, assign(socket, view_assigns(view))}
  end

  defp coordinator_assigns(tournament_id) do
    case GenServer.whereis(TournamentCoordinator.via(tournament_id)) do
      nil ->
        %{
          current_level: nil,
          small_blind: nil,
          big_blind: nil,
          on_break: false,
          remaining: 0,
          tables: %{}
        }

      _pid ->
        tournament_id |> TournamentCoordinator.get_state() |> view_assigns()
    end
  end

  defp view_assigns(view) do
    %{
      current_level: view.current_level,
      small_blind: view.small_blind,
      big_blind: view.big_blind,
      on_break: view.on_break,
      remaining: view.remaining,
      tables: view.tables |> Enum.reject(fn {_slug, ids} -> ids == [] end) |> Enum.sort()
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <.link
          navigate={~p"/tournament"}
          class="text-sm text-base-content/60 hover:text-base-content"
        >
          &larr; Tournament
        </.link>
        <h1 class="mt-1 text-3xl font-bold tracking-tight">{@tournament.name}</h1>

        <div
          :if={@current_level}
          class="mt-2 flex flex-wrap items-center gap-3 text-sm text-base-content/70"
        >
          <span>Level {@current_level} &middot; Blinds {Tokens.format(@small_blind)} / {Tokens.format(
            @big_blind
          )}</span>
          <span :if={@on_break} class="badge badge-warning">On break</span>
          <span class="flex items-center gap-1.5">
            <.icon name="hero-user-group" class="size-4" /> {@remaining} remaining
          </span>
        </div>

        <p :if={is_nil(@current_level)} class="mt-4 text-base-content/70">
          This tournament isn't running right now.
        </p>

        <div :if={@current_level} class="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2">
          <p :if={@tables == []} class="text-base-content/60">No tables are active right now.</p>

          <.link
            :for={{slug, user_ids} <- @tables}
            navigate={~p"/tournament/#{@tournament.id}/tables/#{slug}"}
            id={"tournament-table-#{slug}"}
            class="flex items-center justify-between rounded-box border border-base-300 bg-base-100 p-4 shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-lg"
          >
            <p class="font-semibold">{slug}</p>
            <span class="flex items-center gap-1.5 rounded-full bg-base-200 px-3 py-1 text-sm font-semibold">
              <.icon name="hero-user-group" class="size-4" /> {length(user_ids)} / 8
            </span>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
