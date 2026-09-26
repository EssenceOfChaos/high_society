defmodule HighSocietyWeb.GameLive.Baccarat do
  @moduledoc """
  Punto Banco Baccarat: place Player/Banker/Tie bets, deal, and watch the
  two hands reveal one card at a time - see `HighSociety.Games.Baccarat`
  for the drawing/settlement rules. A round always resolves fully
  server-side in one step (no player decisions once bets are placed); the
  staged reveal here (`deal_step`/`handle_info(:deal_step, ...)`) is purely
  a client-visible pacing device layered on top of the already-final
  result, the same trick `HighSocietyWeb.GameLive.Blackjack` uses for its
  paced initial deal.
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games
  alias HighSociety.Games.Baccarat
  alias HighSociety.Tokens

  @chip_values [100, 500, 2_500, 10_000]

  # A "Bead Road" - the small colored-dot round history every real/online
  # Baccarat table shows - kept only in the LiveView process, not
  # persisted (there's no DB table of past rounds to draw from; only the
  # latest round survives a reconnect, same as `BaccaratGame` itself), so
  # it starts fresh on every page load/reconnect, the same way a real
  # table's bead road resets when the shoe changes. Capped so the strip
  # can't grow unbounded across a very long session.
  @max_history 20

  @impl true
  def mount(_params, _session, socket) do
    baccarat_game = Games.get_active_baccarat_game(socket.assigns.current_scope)

    socket =
      assign(socket,
        page_title: "Baccarat",
        baccarat_game: baccarat_game,
        pending_bets: %{},
        selected_chip: List.first(@chip_values),
        chip_values: @chip_values,
        dealing?: false,
        deal_step: 0,
        error: nil,
        how_to_play_open?: false,
        history: if(baccarat_game, do: [baccarat_game.outcome], else: [])
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("open_how_to_play", _params, socket) do
    {:noreply, assign(socket, :how_to_play_open?, true)}
  end

  def handle_event("close_how_to_play", _params, socket) do
    {:noreply, assign(socket, :how_to_play_open?, false)}
  end

  def handle_event("select_chip", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, selected_chip: String.to_integer(amount))}
  end

  def handle_event("place_bet", _params, %{assigns: %{dealing?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("place_bet", %{"key" => key}, socket) do
    pending_bets =
      Map.update(
        socket.assigns.pending_bets,
        key,
        socket.assigns.selected_chip,
        &min(&1 + socket.assigns.selected_chip, Baccarat.max_bet())
      )

    socket =
      socket
      |> assign(pending_bets: pending_bets, error: nil)
      |> push_event("play_sound", %{sound: "chip-place"})

    {:noreply, socket}
  end

  def handle_event("clear_bets", _params, %{assigns: %{dealing?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("clear_bets", _params, socket) do
    {:noreply, assign(socket, pending_bets: %{}, error: nil)}
  end

  def handle_event("rebet", _params, %{assigns: %{dealing?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("rebet", _params, %{assigns: %{baccarat_game: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("rebet", _params, socket) do
    pending_bets = Map.new(socket.assigns.baccarat_game.bets, &{&1["key"], &1["amount"]})
    {:noreply, assign(socket, pending_bets: pending_bets, error: nil)}
  end

  def handle_event("deal", _params, %{assigns: %{dealing?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("deal", _params, socket) do
    begin_deal(socket, socket.assigns.pending_bets)
  end

  def handle_event("rebet_and_deal", _params, %{assigns: %{dealing?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("rebet_and_deal", _params, %{assigns: %{baccarat_game: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("rebet_and_deal", _params, socket) do
    bets = Map.new(socket.assigns.baccarat_game.bets, &{&1["key"], &1["amount"]})
    begin_deal(socket, bets)
  end

  def handle_event("claim_baccarat_tokens", _params, socket) do
    case Accounts.claim_baccarat_tokens(socket.assigns.current_scope.user) do
      {:ok, user} -> {:noreply, assign(socket, current_scope: Scope.for_user(user))}
      {:error, :already_claimed} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:deal_step, socket) do
    sequence = deal_sequence(socket.assigns.baccarat_game)
    next_step = socket.assigns.deal_step + 1

    socket =
      socket
      |> assign(deal_step: next_step)
      |> push_event("play_sound", %{sound: "card-flip"})

    if next_step < length(sequence) do
      Process.send_after(self(), :deal_step, deal_step_delay())
      {:noreply, socket}
    else
      history =
        (socket.assigns.history ++ [socket.assigns.baccarat_game.outcome])
        |> Enum.take(-@max_history)

      socket =
        socket
        |> assign(dealing?: false, history: history)
        |> push_event("play_sound", %{sound: outcome_sound(socket.assigns.baccarat_game)})

      {:noreply, socket}
    end
  end

  # The order a real dealer moves in: one card to Player, one to Banker,
  # then a second to each - then, only if the drawing rules call for it,
  # Player's third card followed by Banker's. By the time this plays out,
  # `player_hand`/`banker_hand` are already the final, fully-resolved
  # values (see `HighSociety.Games.Baccarat.deal/1`) - purely a client-side
  # reveal pacing device.
  defp deal_sequence(%{player_hand: player_hand, banker_hand: banker_hand}) do
    [:player, :banker, :player, :banker]
    |> maybe_append(:player, length(player_hand) == 3)
    |> maybe_append(:banker, length(banker_hand) == 3)
  end

  defp maybe_append(sequence, side, true), do: sequence ++ [side]
  defp maybe_append(sequence, _side, false), do: sequence

  defp displayed_hand(%{baccarat_game: nil}, _side), do: []

  defp displayed_hand(%{dealing?: true, baccarat_game: game, deal_step: step}, side) do
    revealed = game |> deal_sequence() |> Enum.take(step) |> Enum.count(&(&1 == side))
    game |> full_hand(side) |> Enum.take(revealed)
  end

  defp displayed_hand(%{baccarat_game: game}, side), do: full_hand(game, side)

  defp full_hand(game, :player), do: game.player_hand
  defp full_hand(game, :banker), do: game.banker_hand

  # `nil` while the deal is still being revealed, even though
  # `baccarat_game` itself (the just-resolved round) is already set - the
  # outcome banner and winning-spot highlight only appear once every card
  # has actually been shown.
  defp display_game(%{dealing?: true}), do: nil
  defp display_game(%{baccarat_game: game}), do: game

  defp highlighted_keys(nil), do: MapSet.new()

  defp highlighted_keys(%{bets: bets}) do
    bets |> Enum.filter(& &1["won"]) |> Enum.map(& &1["key"]) |> MapSet.new()
  end

  defp outcome_label("player"), do: "Player wins"
  defp outcome_label("banker"), do: "Banker wins"
  defp outcome_label("tie"), do: "Tie"

  # Standard Bead Road coloring: blue for Player, red for Banker, green
  # for Tie - the same convention every real/online table uses.
  defp history_bead_class("player"), do: "bg-blue-500"
  defp history_bead_class("banker"), do: "bg-red-500"
  defp history_bead_class("tie"), do: "bg-success"

  defp history_bead_label("player"), do: "P"
  defp history_bead_label("banker"), do: "B"
  defp history_bead_label("tie"), do: "T"

  # Which hand won (Player/Banker/Tie) doesn't tell you whether *you*
  # actually made money - a Banker win is a loss for anyone who bet
  # Player, and a Tie pushes Player/Banker bets rather than winning or
  # losing them. What the player actually feels is whether their total
  # payout beat what they wagered, regardless of which side won.
  defp outcome_sound(%{total_payout: payout, total_wager: wager}) do
    cond do
      payout > wager -> "player-wins"
      payout < wager -> "banker-wins"
      true -> "tie"
    end
  end

  # Shared by "deal" (the current pending bets) and "rebet_and_deal" (the
  # previous round's bets, restored and dealt in one click) - everything
  # past "which bets" is identical.
  defp begin_deal(socket, bets) do
    case Games.play_baccarat_round(socket.assigns.current_scope, bets) do
      {:ok, baccarat_game, user} ->
        socket =
          assign(socket,
            baccarat_game: baccarat_game,
            current_scope: Scope.for_user(user),
            dealing?: true,
            deal_step: 0,
            pending_bets: %{},
            error: nil
          )

        Process.send_after(self(), :deal_step, deal_step_delay())
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, error: deal_error_message(reason))}
    end
  end

  defp total_bet(pending_bets), do: pending_bets |> Map.values() |> Enum.sum()

  defp deal_error_message(:no_bets), do: "Place at least one bet before dealing."
  defp deal_error_message(:invalid_bet), do: "That bet isn't valid."

  defp deal_error_message(:bet_too_large),
    do: "Max bet is #{Tokens.format(Baccarat.max_bet())} Tokens per spot."

  defp deal_error_message(:insufficient_funds), do: "You don't have enough Tokens for that bet."

  defp deal_step_delay,
    do: Application.get_env(:high_society, :baccarat_deal_step_delay_ms, 700)

  defp chip_color(100),
    do: "border-neutral-400 bg-gradient-to-br from-white to-neutral-300 text-neutral-900"

  defp chip_color(500), do: "border-red-200 bg-gradient-to-br from-red-500 to-red-800 text-white"

  defp chip_color(2_500),
    do: "border-neutral-400 bg-gradient-to-br from-neutral-700 to-black text-white"

  defp chip_color(10_000),
    do: "border-amber-200 bg-gradient-to-br from-amber-400 to-amber-600 text-amber-950"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :display_game, display_game(assigns))
    assigns = assign(assigns, :highlighted_keys, highlighted_keys(assigns.display_game))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="baccarat-screen"
        class="mx-auto max-w-3xl"
        phx-hook=".SoundEffects"
        data-dealing={to_string(@dealing?)}
      >
        <div class="flex flex-wrap items-center justify-between gap-y-2">
          <div>
            <.link navigate={~p"/#games"} class="text-sm text-base-content/60 hover:text-base-content">
              &larr; All games
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">Baccarat</h1>
          </div>
          <div class="flex flex-wrap items-center justify-end gap-3">
            <div class="text-right">
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/50">
                Balance
              </div>
              <.token_balance amount={@current_scope.user.tokens_balance} />
            </div>
            <button
              :if={is_nil(@current_scope.user.claimed_baccarat_tokens_at)}
              id="claim-baccarat-tokens-button"
              type="button"
              phx-click="claim_baccarat_tokens"
              class="btn btn-success btn-sm animate-pulse"
            >
              Claim {Tokens.format(Accounts.baccarat_starting_token_amount())} Tokens
            </button>
            <button
              id="how-to-play-button"
              type="button"
              phx-click="open_how_to_play"
              class="btn btn-ghost btn-sm btn-circle tooltip tooltip-bottom"
              aria-label="How to play Baccarat"
              data-tip="How to play"
            >
              <.icon name="hero-question-mark-circle" class="size-5" />
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
            <.link
              navigate={~p"/games/baccarat/leaderboard"}
              class="btn btn-ghost btn-sm btn-circle tooltip tooltip-bottom"
              aria-label="Leaderboard"
              data-tip="Leaderboard"
            >
              <.icon name="hero-trophy" class="size-5" />
            </.link>
          </div>
        </div>

        <p :if={@error} class="mt-4 alert alert-error text-sm">{@error}</p>

        <div class="mt-6 rounded-[2rem] border-4 border-amber-700/60 bg-gradient-to-b from-sky-950 via-slate-900 to-black p-4 shadow-2xl ring-2 ring-amber-400/30 sm:p-8">
          <div class="flex items-center justify-between text-[10px] font-semibold uppercase tracking-wide text-amber-200/70">
            <span>Min 0 &middot; Max {Tokens.format(Baccarat.max_bet())}</span>
            <span>Tie pays 8 to 1</span>
          </div>

          <div :if={@history != []} class="mt-3 flex flex-wrap items-center gap-1.5">
            <span class="mr-1 text-[10px] font-semibold uppercase tracking-wide text-sky-300/50">
              History
            </span>
            <span
              :for={outcome <- @history}
              data-history-bead={outcome}
              class={[
                "flex size-5 shrink-0 items-center justify-center rounded-full text-[10px] font-bold text-white",
                history_bead_class(outcome)
              ]}
            >
              {history_bead_label(outcome)}
            </span>
          </div>

          <div class="mt-4 grid grid-cols-2 gap-6">
            <div class="flex flex-col items-center gap-2">
              <span class="text-xs font-bold uppercase tracking-widest text-sky-200">Player</span>
              <div class="flex min-h-24 gap-2">
                <.card_face
                  :for={{card, i} <- Enum.with_index(displayed_hand(assigns, :player))}
                  id={"baccarat-player-card-#{i}"}
                  card={card}
                  deal_animation
                  size={:large}
                />
              </div>
              <span :if={@display_game} class="text-lg font-bold text-sky-100">
                {@display_game.player_total}
              </span>
            </div>

            <div class="flex flex-col items-center gap-2">
              <span class="text-xs font-bold uppercase tracking-widest text-sky-200">Banker</span>
              <div class="flex min-h-24 gap-2">
                <.card_face
                  :for={{card, i} <- Enum.with_index(displayed_hand(assigns, :banker))}
                  id={"baccarat-banker-card-#{i}"}
                  card={card}
                  deal_animation
                  size={:large}
                />
              </div>
              <span :if={@display_game} class="text-lg font-bold text-sky-100">
                {@display_game.banker_total}
              </span>
            </div>
          </div>

          <div class="mt-4 min-h-14 text-center">
            <p :if={@display_game} class="text-lg font-bold text-amber-300">
              {outcome_label(@display_game.outcome)}
            </p>
            <p
              :if={@display_game && @display_game.total_payout > 0}
              class="text-xl font-bold text-success"
            >
              You won {Tokens.format(@display_game.total_payout)} Tokens!
            </p>
            <p :if={@display_game && @display_game.total_payout == 0} class="text-base-content/60">
              No win this round.
            </p>
          </div>

          <div class="mt-6 flex flex-col gap-2">
            <.betting_strip
              label="Tie"
              sub="Pays 8 to 1"
              bet_key="tie"
              amount={Map.get(@pending_bets, "tie", 0)}
              dealing?={@dealing?}
              highlighted={MapSet.member?(@highlighted_keys, "tie")}
            />
            <.betting_strip
              label="Banker"
              sub="Pays 0.95 to 1"
              bet_key="banker"
              amount={Map.get(@pending_bets, "banker", 0)}
              dealing?={@dealing?}
              highlighted={MapSet.member?(@highlighted_keys, "banker")}
            />
            <.betting_strip
              label="Player"
              sub="Pays 1 to 1"
              bet_key="player"
              amount={Map.get(@pending_bets, "player", 0)}
              dealing?={@dealing?}
              highlighted={MapSet.member?(@highlighted_keys, "player")}
            />
          </div>
        </div>

        <div class="mt-8 flex flex-col items-center gap-4">
          <div class="flex flex-wrap items-center justify-center gap-2">
            <button
              :for={chip <- @chip_values}
              id={"chip-#{chip}"}
              type="button"
              phx-click="select_chip"
              phx-value-amount={chip}
              disabled={@dealing?}
              class={[
                "flex size-12 items-center justify-center rounded-full border-4 border-dashed text-xs font-bold shadow-lg shadow-black/40 transition-transform hover:-translate-y-0.5 hover:shadow-xl",
                chip_color(chip),
                @selected_chip == chip && "ring-2 ring-offset-2 ring-offset-base-100 ring-amber-400"
              ]}
            >
              {Tokens.format(chip)}
            </button>
          </div>

          <div class="flex items-center gap-4">
            <div class="text-sm text-base-content/70">
              Total bet:
              <span class="font-bold text-base-content">{Tokens.format(total_bet(@pending_bets))} Tokens</span>
            </div>
            <button
              id="clear-bets-button"
              type="button"
              phx-click="clear_bets"
              disabled={@dealing? or map_size(@pending_bets) == 0}
              class="btn btn-ghost btn-sm"
            >
              Clear bets
            </button>
            <button
              :if={@baccarat_game}
              id="rebet-button"
              type="button"
              phx-click="rebet"
              disabled={@dealing?}
              class="btn btn-outline btn-sm"
            >
              Rebet
            </button>
          </div>

          <div class="flex items-center gap-3">
            <button
              :if={@baccarat_game}
              id="rebet-and-deal-button"
              type="button"
              phx-click="rebet_and_deal"
              disabled={@dealing?}
              class="btn btn-outline btn-lg px-8"
            >
              Rebet &amp; Deal
            </button>
            <button
              id="deal-button"
              type="button"
              phx-click="deal"
              disabled={@dealing? or map_size(@pending_bets) == 0}
              class="btn btn-primary btn-lg px-16"
            >
              {if @dealing?, do: "Dealing…", else: "Deal"}
            </button>
          </div>
        </div>
      </div>

      <.how_to_play_modal :if={@how_to_play_open?} />

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
            this.handleEvent("play_sound", ({sound}) => {
              if (localStorage.getItem("high_society:sound_muted") === "true") return

              new Audio(`/audio/baccarat/${sound}.aac`).play().catch(() => {})
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end

  # Static reference content for the how-to-play modal (`how_to_play_modal/1`).
  @how_to_play_steps [
    %{
      title: "1. Place your bet",
      description: "Choose Player, Banker, or Tie before any cards are dealt."
    },
    %{
      title: "2. The deal",
      description:
        "Two cards each go to Player and Banker. A third card is drawn automatically for either side under fixed rules - there's nothing for you to decide once you've bet."
    },
    %{
      title: "3. Scoring",
      description:
        "Cards 2-9 are face value, 10/J/Q/K are 0, and Ace is 1. Only the last digit of a hand's total counts (7 + 8 = 15, so that hand is worth 5). Whichever side is closer to 9 wins."
    },
    %{
      title: "4. Payouts",
      description:
        "Player pays 1:1, Banker pays 0.95:1 (a 5% commission), and Tie pays 8:1. On a Tie result, Player and Banker bets are simply returned - only Tie bets win or lose."
    }
  ]

  defp how_to_play_modal(assigns) do
    assigns = assign(assigns, :steps, @how_to_play_steps)

    ~H"""
    <div
      id="how-to-play-modal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    >
      <div
        phx-click-away="close_how_to_play"
        class="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-2xl bg-base-100 p-6 shadow-xl"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="text-lg font-bold">How to Play Baccarat</h2>
            <p class="mt-1 text-sm text-base-content/60">
              No decisions once you bet - just watch the cards fall.
            </p>
          </div>
          <button
            type="button"
            phx-click="close_how_to_play"
            class="btn btn-ghost btn-sm btn-circle shrink-0"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <ol class="mt-4 flex flex-col gap-3">
          <li :for={step <- @steps} class="rounded-xl bg-base-200 p-3">
            <p class="font-semibold">{step.title}</p>
            <p class="mt-1 text-sm text-base-content/70">{step.description}</p>
          </li>
        </ol>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :sub, :string, required: true
  attr :bet_key, :string, required: true
  attr :amount, :integer, required: true
  attr :dealing?, :boolean, required: true
  attr :highlighted, :boolean, default: false

  defp betting_strip(assigns) do
    ~H"""
    <button
      id={"bet-#{@bet_key}"}
      type="button"
      phx-click="place_bet"
      phx-value-key={@bet_key}
      disabled={@dealing?}
      class={[
        "flex items-center justify-between gap-3 rounded-full border-2 border-sky-300/40 bg-sky-900/40 px-6 py-3 text-sm font-bold uppercase tracking-widest text-sky-100 transition hover:bg-sky-800/60 disabled:cursor-not-allowed disabled:opacity-60",
        @highlighted && "border-success bg-success/20 text-success"
      ]}
    >
      <span>{@label}</span>
      <span class="text-xs font-normal normal-case text-sky-300/70">{@sub}</span>
      <span
        :if={@amount > 0}
        class="rounded-full bg-amber-400 px-2 py-0.5 text-xs font-bold text-amber-950"
      >
        {Tokens.format(@amount)}
      </span>
    </button>
    """
  end
end
