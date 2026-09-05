defmodule HighSocietyWeb.GameLive.BattleshipLobby do
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games.BattleshipMatch
  alias HighSociety.Games.BattleshipMatches
  alias HighSociety.Money

  @wager_options [5_000, 10_000, 25_000, 50_000]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(HighSociety.PubSub, BattleshipMatches.topic())
    end

    socket =
      assign(socket,
        matches: BattleshipMatches.list_open(),
        wager_options: @wager_options,
        error: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_info({:battleship_lobby_updated, entry}, socket) do
    open? = entry.status in ~w(waiting_for_opponent placing_fleets player_turn opponent_turn)

    matches =
      if open? do
        existing = Enum.reject(socket.assigns.matches, &(&1.slug == entry.slug))
        [entry | existing]
      else
        Enum.reject(socket.assigns.matches, &(&1.slug == entry.slug))
      end
      |> Enum.sort_by(& &1.slug)

    {:noreply, assign(socket, matches: matches)}
  end

  @impl true
  def handle_event("create_match", %{"wager" => wager_str}, socket) do
    with {wager, ""} <- Integer.parse(wager_str),
         true <- wager > 0,
         {:ok, slug} <- BattleshipMatch.create(socket.assigns.current_scope.user, wager) do
      {:noreply, push_navigate(socket, to: ~p"/games/battleship/lobby/#{slug}")}
    else
      {:error, :insufficient_funds} ->
        {:noreply, assign(socket, error: "You don't have enough balance for that wager.")}

      _ ->
        {:noreply, assign(socket, error: "Enter a valid wager.")}
    end
  end

  def handle_event("claim_starting_chips", _params, socket) do
    case Accounts.claim_battleship_chips(socket.assigns.current_scope.user) do
      {:ok, user} -> {:noreply, assign(socket, current_scope: Scope.for_user(user))}
      {:error, :already_claimed} -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <div class="flex items-center justify-between">
          <div>
            <.link
              navigate={~p"/games/battleship"}
              class="text-sm text-base-content/60 hover:text-base-content"
            >
              &larr; Back to Battleship
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">Battleship — Live Matches</h1>
          </div>
          <div class="flex items-center gap-3">
            <div class="text-right">
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/50">
                Balance
              </div>
              <div id="balance" class="text-lg font-bold">
                ${Money.format(@current_scope.user.balance)}
              </div>
            </div>
            <button
              :if={is_nil(@current_scope.user.claimed_battleship_chips_at)}
              id="claim-chips-button"
              type="button"
              phx-click="claim_starting_chips"
              class="btn btn-success btn-sm animate-pulse"
            >
              Claim ${Money.format(Accounts.battleship_starting_chip_amount())} chips
            </button>
          </div>
        </div>
        <p class="mt-2 text-base-content/70">
          Create a match and wait for an opponent, or join one that's open.
        </p>

        <img
          src={~p"/images/pirate-ship-deck.jpg"}
          alt=""
          class="mt-6 h-40 w-full rounded-box object-cover"
        />

        <p :if={@error} class="mt-4 alert alert-error text-sm">{@error}</p>

        <form phx-submit="create_match" class="mt-6 flex items-center gap-2">
          <select name="wager" class="select select-bordered">
            <option :for={amount <- @wager_options} value={amount}>${Money.format(amount)}</option>
          </select>
          <button type="submit" class="btn btn-primary">Create match</button>
        </form>

        <div class="mt-8 grid grid-cols-1 gap-4">
          <p :if={@matches == []} class="text-base-content/60">
            No open matches right now — create one.
          </p>

          <.link
            :for={match <- @matches}
            navigate={~p"/games/battleship/lobby/#{match.slug}"}
            id={"battleship-match-#{match.slug}"}
            class="flex items-center justify-between rounded-box border border-base-300 bg-base-100 p-4 shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-lg"
          >
            <div>
              <p class="font-semibold">${Money.format(match.wager)} wager</p>
              <p class="text-sm text-base-content/60">{status_label(match.status)}</p>
            </div>
            <span class="flex items-center gap-1.5 rounded-full bg-base-200 px-3 py-1 text-sm font-semibold">
              <.icon name="hero-user-group" class="size-4" /> {match.seat_count} / 2
            </span>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp status_label("waiting_for_opponent"), do: "Waiting for an opponent"
  defp status_label("placing_fleets"), do: "Placing fleets"
  defp status_label(status) when status in ["player_turn", "opponent_turn"], do: "In progress"
  defp status_label(status), do: status
end
