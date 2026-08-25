defmodule HighSocietyWeb.GameLive.War do
  use HighSocietyWeb, :live_view

  alias HighSociety.Games
  alias HighSociety.Games.War

  @impl true
  def mount(_params, _session, socket) do
    war_game = Games.get_active_war_game(socket.assigns.current_scope)

    war_game =
      cond do
        war_game -> war_game
        connected?(socket) -> Games.start_war_game(socket.assigns.current_scope)
        true -> nil
      end

    {:ok, assign(socket, war_game: war_game, warring?: false)}
  end

  @impl true
  def handle_event("flip", _params, socket) do
    war_game = Games.play_round(socket.assigns.war_game)
    warring? = war_game.last_round["war?"] || false

    {:noreply, assign(socket, war_game: war_game, warring?: warring?)}
  end

  def handle_event("new_game", _params, socket) do
    war_game = Games.start_war_game(socket.assigns.current_scope)
    {:noreply, assign(socket, war_game: war_game, warring?: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <div class="flex items-center justify-between">
          <div>
            <.link navigate={~p"/"} class="text-sm text-base-content/60 hover:text-base-content">
              &larr; All games
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">War</h1>
          </div>
          <button
            :if={@war_game}
            id="new-game-button"
            phx-click="new_game"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-arrow-path" class="size-4" /> New game
          </button>
        </div>

        <div :if={!@war_game} class="mt-16 flex justify-center">
          <span class="loading loading-spinner loading-lg" />
        </div>

        <div :if={@war_game} id="war-table" class="mt-8">
          <div class="grid grid-cols-2 gap-6">
            <.pile label="You" count={length(@war_game.player_deck)} align="left" />
            <.pile label="Computer" count={length(@war_game.computer_deck)} align="right" />
          </div>

          <div :for={tie <- ties(@war_game)} class="mt-8 grid grid-cols-2 gap-6">
            <div class="flex flex-col items-center gap-1">
              <span class="text-xs font-semibold uppercase tracking-wide text-base-content/40">
                Tied — burned
              </span>
              <.card_face card={tie["player_card"]} dim />
            </div>
            <div class="flex flex-col items-center gap-1">
              <span class="text-xs font-semibold uppercase tracking-wide text-base-content/40">
                Tied — burned
              </span>
              <.card_face card={tie["computer_card"]} dim />
            </div>
          </div>

          <div class="mt-8 grid grid-cols-2 gap-6">
            <div class="flex flex-col items-center gap-1">
              <span
                :if={war_round?(@war_game)}
                class="text-xs font-semibold uppercase tracking-wide text-warning"
              >
                Tiebreaker
              </span>
              <.card_face card={last_card(@war_game, :player_card)} />
            </div>
            <div class="flex flex-col items-center gap-1">
              <span
                :if={war_round?(@war_game)}
                class="text-xs font-semibold uppercase tracking-wide text-warning"
              >
                Tiebreaker
              </span>
              <.card_face card={last_card(@war_game, :computer_card)} />
            </div>
          </div>

          <div class="mt-6 text-center min-h-8">
            <p
              :if={@war_game.last_round && @war_game.status == "in_progress"}
              class={[@warring? && "font-bold text-warning text-lg", !@warring? && "text-base-content/70"]}
            >
              {round_message(@war_game.last_round)}
            </p>
          </div>

          <div class="mt-6 flex justify-center">
            <button
              :if={@war_game.status == "in_progress"}
              id="flip-button"
              phx-click="flip"
              class="btn btn-primary btn-lg px-12"
            >
              Flip
            </button>

            <div :if={@war_game.status != "in_progress"} id="game-result" class="text-center">
              <p class={[
                "text-2xl font-bold",
                @war_game.status == "player_won" && "text-success",
                @war_game.status == "computer_won" && "text-error"
              ]}>
                <%= if @war_game.status == "player_won" do %>
                  You won the game! 🎉
                <% else %>
                  The computer won this one.
                <% end %>
              </p>
              <button id="play-again-button" phx-click="new_game" class="btn btn-primary mt-4">
                Play again
              </button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :align, :string, required: true

  defp pile(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1", @align == "right" && "items-end"]}>
      <span class="text-sm font-medium text-base-content/50">{@label}</span>
      <span class="text-2xl font-bold">{@count}
      <span class="text-sm font-normal text-base-content/50">cards</span></span>
    </div>
    """
  end

  attr :card, :string, default: nil
  attr :dim, :boolean, default: false

  defp card_face(assigns) do
    {rank, suit} = if assigns.card, do: War.split(assigns.card), else: {nil, nil}

    assigns =
      assigns
      |> assign(:rank, rank)
      |> assign(:suit_symbol, suit_symbol(suit))
      |> assign(:red?, suit in ["H", "D"])

    ~H"""
    <div class={[
      "flex h-40 w-28 flex-col items-center justify-center rounded-xl border-2 shadow-md",
      if(@card, do: "bg-white border-base-300", else: "border-dashed border-base-300 bg-base-200"),
      @dim && "opacity-40 scale-90"
    ]}>
      <div
        :if={@card}
        class={["flex flex-col items-center", @red? && "text-red-600", !@red? && "text-neutral-900"]}
      >
        <span class="text-3xl font-bold">{@rank}</span>
        <span class="text-4xl leading-none">{@suit_symbol}</span>
      </div>
      <.icon :if={!@card} name="hero-question-mark-circle" class="size-8 text-base-content/20" />
    </div>
    """
  end

  defp suit_symbol("S"), do: "♠"
  defp suit_symbol("H"), do: "♥"
  defp suit_symbol("D"), do: "♦"
  defp suit_symbol("C"), do: "♣"
  defp suit_symbol(_), do: nil

  defp last_card(%{last_round: nil}, _key), do: nil
  defp last_card(%{last_round: last_round}, key), do: Map.get(last_round, Atom.to_string(key))

  defp ties(%{last_round: nil}), do: []
  defp ties(%{last_round: last_round}), do: Map.get(last_round, "ties") || []

  defp war_round?(%{last_round: nil}), do: false
  defp war_round?(%{last_round: last_round}), do: Map.get(last_round, "war?") || false

  defp round_message(%{"winner" => "player", "cards_won" => n, "war?" => true}),
    do: "WAR! Your tiebreaker won — you took #{n} cards total."

  defp round_message(%{"winner" => "computer", "cards_won" => n, "war?" => true}),
    do: "WAR! The computer's tiebreaker won — it took #{n} cards total."

  defp round_message(%{"winner" => "player", "cards_won" => n}),
    do: "You won that round and took #{n} cards."

  defp round_message(%{"winner" => "computer", "cards_won" => n}),
    do: "The computer won that round and took #{n} cards."
end
