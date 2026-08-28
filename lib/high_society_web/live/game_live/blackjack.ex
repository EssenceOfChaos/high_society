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
       second_hand?: false,
       round_dismissed?: false,
       bet_error: nil
     )}
  end

  @impl true
  def handle_event("add_second_hand", _params, socket) do
    {:noreply, assign(socket, second_hand?: true)}
  end

  def handle_event("remove_second_hand", _params, socket) do
    socket =
      assign(socket,
        pending_bets: Map.put(socket.assigns.pending_bets, 1, 0),
        second_hand?: false
      )

    {:noreply, socket}
  end

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

        socket =
          socket
          |> assign(pending_bets: %{0 => 0, 1 => 0}, round_dismissed?: false, bet_error: nil)
          |> update_blackjack_game(blackjack_game, user)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, bet_error: bet_error_message(reason))}
    end
  end

  def handle_event("hit", _params, socket) do
    {blackjack_game, user} =
      Games.hit(socket.assigns.current_scope, socket.assigns.blackjack_game)

    {:noreply, update_blackjack_game(socket, blackjack_game, user)}
  end

  def handle_event("stand", _params, socket) do
    {blackjack_game, user} =
      Games.stand(socket.assigns.current_scope, socket.assigns.blackjack_game)

    {:noreply, update_blackjack_game(socket, blackjack_game, user)}
  end

  def handle_event("double_down", _params, socket) do
    case Games.double_down(socket.assigns.current_scope, socket.assigns.blackjack_game) do
      {:ok, blackjack_game, user} ->
        {:noreply, update_blackjack_game(socket, blackjack_game, user)}

      {:error, :insufficient_funds} ->
        {:noreply, put_flash(socket, :error, "You don't have enough chips to double down.")}

      {:error, :invalid_action} ->
        {:noreply, socket}
    end
  end

  def handle_event("split", _params, socket) do
    case Games.split(socket.assigns.current_scope, socket.assigns.blackjack_game) do
      {:ok, blackjack_game, user} ->
        {:noreply, update_blackjack_game(socket, blackjack_game, user)}

      {:error, :insufficient_funds} ->
        {:noreply, put_flash(socket, :error, "You don't have enough chips to split.")}

      {:error, :invalid_action} ->
        {:noreply, socket}
    end
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
  def handle_info(:dealer_step, socket) do
    {blackjack_game, user} =
      Games.dealer_step(socket.assigns.current_scope, socket.assigns.blackjack_game)

    {:noreply, update_blackjack_game(socket, blackjack_game, user)}
  end

  # Applies a freshly-persisted game (and possibly-credited user) to the
  # socket. When the game has just entered (or is still in) the dealer's
  # turn, plays the matching reveal/hit sound and schedules the next paced
  # step, so the dealer's hole-card reveal and subsequent hits/busts play
  # out one card at a time instead of resolving instantly.
  defp update_blackjack_game(socket, %{status: "dealer_turn"} = blackjack_game, user) do
    sound = if length(blackjack_game.dealer_hand) == 2, do: "flip", else: "deal"
    Process.send_after(self(), :dealer_step, dealer_step_delay())

    socket
    |> assign(blackjack_game: blackjack_game, current_scope: Scope.for_user(user))
    |> push_event("play_sound", %{sound: sound})
  end

  defp update_blackjack_game(socket, blackjack_game, user) do
    assign(socket, blackjack_game: blackjack_game, current_scope: Scope.for_user(user))
  end

  defp dealer_step_delay,
    do: Application.get_env(:high_society, :blackjack_dealer_step_delay_ms, 900)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="blackjack-screen" class="mx-auto max-w-3xl" phx-hook=".SoundEffects">
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
            <button
              id="sound-toggle-button"
              type="button"
              phx-hook=".SoundToggle"
              class="btn btn-ghost btn-sm btn-circle"
              aria-label="Toggle sound"
              aria-pressed="true"
            >
              <.icon name="hero-speaker-wave" class="size-4 sound-on-icon" />
              <.icon name="hero-speaker-x-mark" class="size-4 sound-off-icon hidden" />
            </button>
          </div>
        </div>

        <div :if={betting?(assigns)} id="betting-area" class="mt-10">
          <div class={[
            "grid gap-6",
            @second_hand? && "grid-cols-2",
            !@second_hand? && "grid-cols-1 justify-items-center"
          ]}>
            <.betting_box box={0} amount={@pending_bets[0]} closable?={false} />
            <.betting_box :if={@second_hand?} box={1} amount={@pending_bets[1]} closable?={true} />
          </div>

          <div :if={!@second_hand?} class="mt-4 flex justify-center">
            <button
              id="add-second-hand-button"
              type="button"
              phx-click="add_second_hand"
              class="btn btn-outline btn-sm"
            >
              + Play a second hand
            </button>
          </div>

          <p class="mt-4 text-center text-xs text-base-content/50">
            Max ${format_money(Blackjack.max_bet())} per hand.
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
          <div
            class="relative flex flex-col items-center gap-2 rounded-t-2xl bg-cover bg-top px-4 pb-6 pt-6 shadow-xl"
            style="background-image: url(/images/blackjack-felt.png);"
          >
            <span class="rounded-full bg-black/55 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-amber-100 shadow">
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

          <div class="rounded-b-2xl bg-gradient-to-b from-[#241608] to-[#150c04] px-4 pb-6 pt-8 shadow-xl ring-1 ring-black/40">
            <div class={[
              "grid gap-6",
              length(@blackjack_game.hands) == 1 && "grid-cols-1 justify-items-center",
              length(@blackjack_game.hands) > 1 && "grid-cols-2"
            ]}>
              <.hand_box
                :for={hand <- @blackjack_game.hands}
                hand={hand}
                label={hand_label(@blackjack_game.hands, hand)}
                active?={@blackjack_game.active_hand == hand["id"]}
                status={@blackjack_game.status}
                can_double_down?={Games.can_double_down?(@blackjack_game)}
                can_split?={Games.can_split?(@blackjack_game)}
              />
            </div>

            <div :if={@blackjack_game.status == "round_over"} class="mt-8 flex justify-center">
              <button
                id="new-round-button"
                type="button"
                phx-click="new_round"
                class="btn btn-lg border-none bg-amber-500 px-12 text-amber-950 hover:bg-amber-400"
              >
                New round
              </button>
            </div>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SoundToggle">
        export default {
          mounted() {
            this.storageKey = "high_society:sound_muted"
            this.onIcon = this.el.querySelector(".sound-on-icon")
            this.offIcon = this.el.querySelector(".sound-off-icon")
            this.applyState(this.isMuted())

            this.el.addEventListener("click", () => {
              const muted = !this.isMuted()
              localStorage.setItem(this.storageKey, muted ? "true" : "false")
              this.applyState(muted)
            })
          },
          isMuted() {
            return localStorage.getItem(this.storageKey) === "true"
          },
          applyState(muted) {
            this.onIcon.classList.toggle("hidden", muted)
            this.offIcon.classList.toggle("hidden", !muted)
            this.el.setAttribute("aria-pressed", muted ? "false" : "true")
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SoundEffects">
        export default {
          mounted() {
            this.sounds = {
              deal: new Audio("/audio/card-deal.mp3"),
              flip: new Audio("/audio/card-flip.mp3")
            }

            this.handleEvent("play_sound", ({sound}) => {
              if (localStorage.getItem("high_society:sound_muted") === "true") return

              const audio = this.sounds[sound]
              if (!audio) return

              audio.currentTime = 0
              audio.play().catch(() => {})
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  attr :box, :integer, required: true
  attr :amount, :integer, required: true
  attr :closable?, :boolean, required: true

  defp betting_box(assigns) do
    ~H"""
    <div
      id={"betting-box-#{@box}"}
      class="relative flex flex-col items-center gap-3 rounded-2xl border-2 border-dashed border-base-300 bg-base-200 p-4"
    >
      <button
        :if={@closable?}
        id={"remove-second-hand-button"}
        type="button"
        phx-click="remove_second_hand"
        class="btn btn-ghost btn-xs btn-circle absolute right-2 top-2"
        aria-label="Remove second hand"
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
      <span class="text-xs font-semibold uppercase tracking-wide text-base-content/50">
        Hand {@box + 1}
      </span>
      <div id={"bet-amount-#{@box}"} class="text-2xl font-bold">${format_money(@amount)}</div>
      <div class="flex flex-wrap justify-center gap-2">
        <button
          :for={chip <- chip_values()}
          id={"chip-#{@box}-#{chip}"}
          type="button"
          phx-click="add_chip"
          phx-value-box={@box}
          phx-value-amount={chip}
          class={[
            "flex size-12 items-center justify-center rounded-full border-4 border-dashed text-xs font-bold shadow-md transition-transform hover:-translate-y-0.5",
            chip_color(chip)
          ]}
        >
          ${chip}
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

  defp chip_color(5), do: "border-neutral-400 bg-neutral-100 text-neutral-900"
  defp chip_color(25), do: "border-red-300 bg-red-600 text-white"
  defp chip_color(100), do: "border-neutral-600 bg-neutral-900 text-white"
  defp chip_color(500), do: "border-amber-300 bg-amber-500 text-amber-950"

  attr :hand, :map, required: true
  attr :label, :string, required: true
  attr :active?, :boolean, required: true
  attr :status, :string, required: true
  attr :can_double_down?, :boolean, required: true
  attr :can_split?, :boolean, required: true

  defp hand_box(assigns) do
    ~H"""
    <div
      id={"hand-box-#{@hand["id"]}"}
      class={[
        "flex w-full flex-col items-center gap-2 rounded-2xl p-3 transition-colors duration-500",
        @active? && "bg-amber-400/10 ring-2 ring-amber-400"
      ]}
    >
      <span class="text-xs font-semibold uppercase tracking-wide text-amber-100/60">
        {@label} — Bet ${format_money(@hand["bet"])}{if @hand["doubled"], do: " (doubled)"} — {Blackjack.value(
          @hand["cards"]
        )}
      </span>
      <div id={"hand-cards-#{@hand["id"]}"} class="flex w-full justify-center gap-2">
        <.card_face :for={card <- @hand["cards"]} card={card} />
      </div>
      <p
        :if={@hand["outcome"]}
        class={[
          "text-sm font-semibold",
          @hand["outcome"] in ["win", "blackjack_win"] && "text-emerald-400",
          @hand["outcome"] == "push" && "text-amber-100/70",
          @hand["outcome"] == "loss" && "text-red-400"
        ]}
      >
        {outcome_message(@hand)}
      </p>
      <div :if={@active? && @status == "player_turn"} class="mt-2 flex gap-2">
        <button
          id={"hit-button-#{@hand["id"]}"}
          type="button"
          phx-click="hit"
          class="btn btn-sm border-none bg-emerald-600 text-white hover:bg-emerald-500"
        >
          Hit
        </button>
        <button
          id={"stand-button-#{@hand["id"]}"}
          type="button"
          phx-click="stand"
          class="btn btn-sm border-none bg-red-700 text-white hover:bg-red-600"
        >
          Stand
        </button>
        <button
          :if={@can_double_down?}
          id={"double-button-#{@hand["id"]}"}
          type="button"
          phx-click="double_down"
          class="btn btn-sm border-none bg-indigo-600 text-white hover:bg-indigo-500"
        >
          Double
        </button>
        <button
          :if={@can_split?}
          id={"split-button-#{@hand["id"]}"}
          type="button"
          phx-click="split"
          class="btn btn-sm border-none bg-amber-600 text-white hover:bg-amber-500"
        >
          Split
        </button>
      </div>
    </div>
    """
  end

  # Both boxes are always dealt a single hand, but a split turns one box
  # into two - "Hand 1" stays as-is, and its two post-split hands become
  # "Hand 1A"/"Hand 1B" (in play order) so they're distinguishable without
  # exposing the internal `id` scheme.
  defp hand_label(hands, hand) do
    siblings = Enum.filter(hands, &(&1["box"] == hand["box"]))

    case siblings do
      [_single] ->
        "Hand #{hand["box"] + 1}"

      _multiple ->
        letter = Enum.find_index(siblings, &(&1["id"] == hand["id"])) |> then(&Enum.at(["A", "B"], &1))
        "Hand #{hand["box"] + 1}#{letter}"
    end
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
