defmodule HighSocietyWeb.GameLive.Blackjack do
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games
  alias HighSociety.Games.Blackjack

  @impl true
  def mount(_params, _session, socket) do
    blackjack_game = Games.get_active_blackjack_game(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       blackjack_game: blackjack_game,
       pending_bets: %{0 => 0, 1 => 0},
       round_dismissed?: false,
       bet_error: nil
     )}
  end

  @impl true
  def handle_event("add_chip", %{"box" => box, "amount" => amount}, socket) do
    box = String.to_integer(box)
    amount = String.to_integer(amount)

    pending_bets =
      Map.update!(socket.assigns.pending_bets, box, &min(&1 + amount, Blackjack.max_bet()))

    {:noreply, assign(socket, pending_bets: pending_bets)}
  end

  def handle_event("clear_bet", %{"box" => box}, socket) do
    box = String.to_integer(box)
    {:noreply, assign(socket, pending_bets: Map.put(socket.assigns.pending_bets, box, 0))}
  end

  def handle_event("deal", _params, socket) do
    bets = socket.assigns.pending_bets |> Enum.reject(fn {_box, amt} -> amt <= 0 end) |> Map.new()

    case Games.start_blackjack_round(socket.assigns.current_scope, bets) do
      {:ok, blackjack_game} ->
        user = Accounts.get_user!(socket.assigns.current_scope.user.id)

        {:noreply,
         assign(socket,
           blackjack_game: blackjack_game,
           pending_bets: %{0 => 0, 1 => 0},
           round_dismissed?: false,
           bet_error: nil,
           current_scope: Scope.for_user(user)
         )}

      {:error, reason} ->
        {:noreply, assign(socket, bet_error: bet_error_message(reason))}
    end
  end

  def handle_event("hit", _params, socket) do
    {blackjack_game, user} =
      Games.hit(socket.assigns.current_scope, socket.assigns.blackjack_game)

    {:noreply,
     assign(socket, blackjack_game: blackjack_game, current_scope: Scope.for_user(user))}
  end

  def handle_event("stand", _params, socket) do
    {blackjack_game, user} =
      Games.stand(socket.assigns.current_scope, socket.assigns.blackjack_game)

    {:noreply,
     assign(socket, blackjack_game: blackjack_game, current_scope: Scope.for_user(user))}
  end

  def handle_event("new_round", _params, socket) do
    {:noreply, assign(socket, round_dismissed?: true)}
  end

  def handle_event("claim_starting_chips", _params, socket) do
    case Accounts.claim_starting_chips(socket.assigns.current_scope.user) do
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
            <.link navigate={~p"/"} class="text-sm text-base-content/60 hover:text-base-content">
              &larr; All games
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">Blackjack</h1>
          </div>
          <div class="flex items-center gap-3">
            <div class="text-right">
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/50">
                Balance
              </div>
              <div id="balance" class="text-lg font-bold">
                ${format_money(@current_scope.user.balance)}
              </div>
            </div>
            <button
              :if={is_nil(@current_scope.user.claimed_starting_chips_at)}
              id="claim-chips-button"
              type="button"
              phx-click="claim_starting_chips"
              class="btn btn-success btn-sm"
            >
              Claim ${format_money(Accounts.starting_chip_amount())}
            </button>
          </div>
        </div>

        <div :if={betting?(assigns)} id="betting-area" class="mt-10">
          <div class="grid grid-cols-2 gap-6">
            <.betting_box box={0} amount={@pending_bets[0]} />
            <.betting_box box={1} amount={@pending_bets[1]} />
          </div>

          <p class="mt-4 text-center text-xs text-base-content/50">
            Max ${format_money(Blackjack.max_bet())} per box.
          </p>

          <div class="mt-6 flex flex-col items-center gap-2">
            <p :if={@bet_error} id="bet-error" class="text-sm font-medium text-error">
              {@bet_error}
            </p>
            <button
              id="deal-button"
              type="button"
              phx-click="deal"
              disabled={total_bet(@pending_bets) == 0}
              class="btn btn-primary btn-lg px-12"
            >
              Deal
            </button>
          </div>
        </div>

        <div :if={!betting?(assigns)} id="blackjack-table" class="mt-8">
          <div class="flex flex-col items-center gap-2">
            <span class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
              Dealer<span :if={@blackjack_game.status != "player_turn"}>
                — {Blackjack.value(@blackjack_game.dealer_hand)}
              </span>
            </span>
            <div id="dealer-cards" class="flex w-full justify-center gap-2">
              <.card_face
                :for={{card, index} <- Enum.with_index(@blackjack_game.dealer_hand)}
                card={card}
                face_down={index == 1 && @blackjack_game.status == "player_turn"}
              />
            </div>
          </div>

          <div class={[
            "mt-10 grid gap-6",
            length(@blackjack_game.hands) == 2 && "grid-cols-2",
            length(@blackjack_game.hands) == 1 && "grid-cols-1 justify-items-center"
          ]}>
            <.hand_box
              :for={hand <- @blackjack_game.hands}
              hand={hand}
              active?={@blackjack_game.active_hand == hand["box"]}
              status={@blackjack_game.status}
            />
          </div>

          <div :if={@blackjack_game.status == "round_over"} class="mt-8 flex justify-center">
            <button id="new-round-button" type="button" phx-click="new_round" class="btn btn-primary">
              New round
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :box, :integer, required: true
  attr :amount, :integer, required: true

  defp betting_box(assigns) do
    ~H"""
    <div
      id={"betting-box-#{@box}"}
      class="flex flex-col items-center gap-3 rounded-2xl border-2 border-dashed border-base-300 bg-base-200 p-4"
    >
      <span class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
        Box {@box + 1}
      </span>
      <div id={"bet-amount-#{@box}"} class="text-2xl font-bold">${format_money(@amount)}</div>
      <div class="flex flex-wrap justify-center gap-1">
        <button
          :for={chip <- chip_values()}
          id={"chip-#{@box}-#{chip}"}
          type="button"
          phx-click="add_chip"
          phx-value-box={@box}
          phx-value-amount={chip}
          class="btn btn-xs btn-outline"
        >
          +${chip}
        </button>
      </div>
      <button
        :if={@amount > 0}
        id={"clear-bet-#{@box}"}
        type="button"
        phx-click="clear_bet"
        phx-value-box={@box}
        class="btn btn-ghost btn-xs"
      >
        Clear
      </button>
    </div>
    """
  end

  attr :hand, :map, required: true
  attr :active?, :boolean, required: true
  attr :status, :string, required: true

  defp hand_box(assigns) do
    ~H"""
    <div
      id={"hand-box-#{@hand["box"]}"}
      class={[
        "flex w-full flex-col items-center gap-2 rounded-2xl p-3 transition-colors duration-500",
        @active? && "border-2 border-warning bg-warning/10"
      ]}
    >
      <span class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
        Box {@hand["box"] + 1} — Bet ${format_money(@hand["bet"])} — {Blackjack.value(@hand["cards"])}
      </span>
      <div id={"hand-cards-#{@hand["box"]}"} class="flex w-full justify-center gap-2">
        <.card_face :for={card <- @hand["cards"]} card={card} />
      </div>
      <p
        :if={@hand["outcome"]}
        class={[
          "text-sm font-semibold",
          @hand["outcome"] in ["win", "blackjack_win"] && "text-success",
          @hand["outcome"] == "push" && "text-base-content/70",
          @hand["outcome"] == "loss" && "text-error"
        ]}
      >
        {outcome_message(@hand)}
      </p>
      <div :if={@active? && @status == "player_turn"} class="mt-2 flex gap-2">
        <button
          id={"hit-button-#{@hand["box"]}"}
          type="button"
          phx-click="hit"
          class="btn btn-primary btn-sm"
        >
          Hit
        </button>
        <button
          id={"stand-button-#{@hand["box"]}"}
          type="button"
          phx-click="stand"
          class="btn btn-outline btn-sm"
        >
          Stand
        </button>
      </div>
    </div>
    """
  end

  defp betting?(assigns), do: is_nil(assigns.blackjack_game) or assigns.round_dismissed?

  defp chip_values, do: [5, 25, 100, 500]

  defp total_bet(pending_bets), do: pending_bets |> Map.values() |> Enum.sum()

  defp bet_error_message(:no_bets), do: "Place a bet on at least one box before dealing."

  defp bet_error_message(:bet_too_large),
    do: "Max bet is $#{format_money(Blackjack.max_bet())} per box."

  defp bet_error_message(:insufficient_funds), do: "You don't have enough chips for that bet."

  defp outcome_message(%{"outcome" => "blackjack_win", "payout" => payout}),
    do: "Blackjack! +$#{format_money(payout)}"

  defp outcome_message(%{"outcome" => "win", "payout" => payout}),
    do: "Win +$#{format_money(payout)}"

  defp outcome_message(%{"outcome" => "push", "payout" => payout}),
    do: "Push — $#{format_money(payout)} returned"

  defp outcome_message(%{"outcome" => "loss"}), do: "Loss"
  defp outcome_message(_hand), do: nil

  defp format_money(amount) when is_integer(amount) do
    amount
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
