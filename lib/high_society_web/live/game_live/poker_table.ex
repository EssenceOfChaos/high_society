defmodule HighSocietyWeb.GameLive.PokerTable do
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games.Poker
  alias HighSociety.Games.Poker.HandEvaluator
  alias HighSociety.Games.PokerTable
  alias HighSociety.Games.PokerTables
  alias HighSocietyWeb.Presence

  # Screen slots for up to 8 seats, arranged clockwise around the felt
  # starting at bottom-center - seat 0 always renders there so a seated
  # viewer sees their own seat in the conventional "you're at the bottom"
  # spot, with the rest following clockwise from it.
  @seat_positions [
    %{top: 94, left: 50},
    %{top: 80, left: 90},
    %{top: 48, left: 99},
    %{top: 12, left: 88},
    %{top: 0, left: 50},
    %{top: 12, left: 12},
    %{top: 48, left: 1},
    %{top: 80, left: 10}
  ]

  # The felt's center, where the pot sits - used to place each seat's bet
  # chips partway between that seat and the pot.
  @center %{top: 50, left: 50}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case PokerTables.get(slug) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "That table doesn't exist.")
          |> push_navigate(to: ~p"/games/poker")

        {:ok, socket}

      table_config ->
        topic = PokerTable.topic(slug)

        if connected?(socket) do
          Phoenix.PubSub.subscribe(HighSociety.PubSub, topic)
          {:ok, _ref} = Presence.track(self(), topic, socket.assigns.current_scope.user.id, %{})
        end

        state =
          if connected?(socket),
            do: PokerTable.get_state(slug),
            else: %{
              seats: %{},
              button_seat: nil,
              hand: nil,
              action_deadline: nil,
              config: table_config
            }

        viewer_count = if connected?(socket), do: topic |> Presence.list() |> map_size(), else: 0

        socket =
          assign(socket,
            slug: slug,
            table: table_config,
            state: state,
            viewer_count: viewer_count,
            join_seat: nil,
            buy_in_amount: nil,
            action_error: nil
          )

        {:ok, socket}
    end
  end

  @impl true
  def handle_info({:poker_table_updated, view}, socket) do
    socket =
      socket
      |> assign(:state, view)
      |> push_action_sound(view.last_action)

    {:noreply, socket}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    count = socket.assigns.slug |> PokerTable.topic() |> Presence.list() |> map_size()
    {:noreply, assign(socket, :viewer_count, count)}
  end

  @impl true
  def handle_event("open_join", %{"seat" => seat}, socket) do
    socket =
      assign(socket,
        join_seat: String.to_integer(seat),
        buy_in_amount: PokerTables.min_buy_in(socket.assigns.table),
        action_error: nil
      )

    {:noreply, socket}
  end

  def handle_event("close_join", _params, socket),
    do: {:noreply, assign(socket, join_seat: nil, action_error: nil)}

  def handle_event("set_buy_in", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, :buy_in_amount, String.to_integer(amount))}
  end

  def handle_event("confirm_join", _params, socket) do
    user = socket.assigns.current_scope.user

    case PokerTable.sit(
           socket.assigns.slug,
           user,
           socket.assigns.join_seat,
           socket.assigns.buy_in_amount
         ) do
      {:ok, view} ->
        socket =
          assign(socket,
            state: view,
            join_seat: nil,
            current_scope: Scope.for_user(Accounts.get_user!(user.id))
          )

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :action_error, join_error_message(reason))}
    end
  end

  def handle_event("leave_table", _params, socket) do
    user = socket.assigns.current_scope.user

    case PokerTable.stand(socket.assigns.slug, user.id) do
      {:ok, view} ->
        socket =
          assign(socket, state: view, current_scope: Scope.for_user(Accounts.get_user!(user.id)))

        {:noreply, socket}

      {:error, :not_seated} ->
        {:noreply, socket}
    end
  end

  def handle_event("act", %{"action" => action}, socket),
    do: perform_action(socket, String.to_existing_atom(action), nil)

  def handle_event("bet_or_raise", %{"amount" => amount}, socket) do
    action = if socket.assigns.state.hand.current_bet == 0, do: :bet, else: :raise
    perform_action(socket, action, String.to_integer(amount))
  end

  def handle_event("claim_poker_chips", _params, socket) do
    case Accounts.claim_poker_chips(socket.assigns.current_scope.user) do
      {:ok, user} -> {:noreply, assign(socket, current_scope: Scope.for_user(user))}
      {:error, :already_claimed} -> {:noreply, socket}
    end
  end

  defp perform_action(socket, action, amount) do
    user = socket.assigns.current_scope.user

    case PokerTable.act(socket.assigns.slug, user.id, action, amount) do
      {:ok, view} -> {:noreply, assign(socket, state: view, action_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, :action_error, action_error_message(reason))}
    end
  end

  defp push_action_sound(socket, nil), do: socket

  defp push_action_sound(socket, %{action: action, all_in: all_in}),
    do: push_event(socket, "play_sound", %{sound: action_sound(action, all_in)})

  defp action_sound(_action, true), do: "all-in"
  defp action_sound(:check, false), do: "check"
  defp action_sound(:fold, false), do: "fold"
  defp action_sound(:call, false), do: "bet"
  defp action_sound(:bet, false), do: "bet"
  defp action_sound(:raise, false), do: "raise"

  defp join_error_message(:seat_taken), do: "Someone just took that seat."
  defp join_error_message(:already_seated), do: "You're already seated at this table."
  defp join_error_message(:invalid_buy_in), do: "That buy-in is outside the table's range."
  defp join_error_message(:insufficient_funds), do: "You don't have enough chips for that buy-in."
  defp join_error_message(_reason), do: "Couldn't sit down."

  defp action_error_message(:not_your_turn), do: "It's not your turn."
  defp action_error_message(:bet_outstanding), do: "There's a bet to call - you can't check."
  defp action_error_message(:nothing_to_call), do: "Nothing to call."

  defp action_error_message(:bet_already_outstanding),
    do: "There's already a bet - raise instead."

  defp action_error_message(:no_bet_to_raise), do: "There's nothing to raise yet - bet instead."
  defp action_error_message(:below_minimum), do: "That's below the minimum bet."
  defp action_error_message(:below_minimum_raise), do: "That's below the minimum raise."
  defp action_error_message(:must_exceed_current_bet), do: "A raise must exceed the current bet."
  defp action_error_message(:exceeds_stack), do: "You don't have that many chips."
  defp action_error_message(_reason), do: "Couldn't complete that action."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :my_turn?, my_turn?(assigns.state, assigns.current_scope.user.id))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="poker-table-screen"
        class={["mx-auto max-w-4xl", @my_turn? && "pb-28"]}
        phx-hook=".SoundEffects"
      >
        <div class="flex items-center justify-between">
          <div>
            <.link
              navigate={~p"/games/poker"}
              class="text-sm text-base-content/60 hover:text-base-content"
            >
              &larr; All tables
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">{@table.name}</h1>
            <p class="text-sm text-base-content/50">
              Blinds ${@table.small_blind} / ${@table.big_blind} &middot;
              <.icon name="hero-eye" class="-mt-0.5 inline size-4" /> {@viewer_count} watching
            </p>
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
              :if={is_nil(@current_scope.user.claimed_poker_chips_at)}
              id="claim-poker-chips-button"
              type="button"
              phx-click="claim_poker_chips"
              class="btn btn-success btn-sm animate-pulse"
            >
              Claim ${format_money(Accounts.poker_starting_chip_amount())}
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

        <p
          :if={@action_error}
          id="action-error"
          class="mt-4 text-center text-sm font-medium text-error"
        >
          {@action_error}
        </p>

        <div
          id="poker-felt"
          class="relative mt-6 aspect-[7/5] w-full rounded-3xl bg-gradient-to-b from-emerald-900 to-emerald-950 shadow-xl ring-1 ring-black/40"
        >
          <div class="absolute left-1/2 top-1/2 flex w-max -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-2">
            <div id="community-cards" class="flex gap-2">
              <.card_face :for={card <- community_card_slots(@state.hand)} card={card} />
            </div>
          </div>

          <p
            :if={@state.hand && @state.hand.status == :hand_over}
            id="winner-banner"
            class="absolute inset-x-0 top-3 mx-auto w-fit animate-bounce rounded-full bg-black/60 px-4 py-1 text-center text-sm font-bold text-amber-300 [animation-iteration-count:2]"
          >
            {winner_text(@state.hand)}
          </p>

          <div
            :if={pot_total(@state.hand) > 0}
            id="pot-chips"
            class="absolute flex -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1 transition-all duration-700 ease-out"
            phx-hook=".InlineStyle"
            data-style={"top: #{pot_chip_position(@state.hand).top}%; left: #{pot_chip_position(@state.hand).left}%;"}
          >
            <.chip_stack id="pot-chips-stack" amount={pot_total(@state.hand)} chip_size="size-7" />
            <div class="rounded-full bg-black/50 px-4 py-1 text-sm font-semibold text-amber-200">
              Pot: ${format_money(pot_total(@state.hand))}
            </div>
          </div>

          <.seat
            :for={seat_index <- 0..(PokerTables.seats() - 1)}
            seat_index={seat_index}
            position={seat_position(seat_index)}
            seat={Map.get(@state.seats, seat_index)}
            hand={@state.hand}
            button_seat={@state.button_seat}
            action_deadline={@state.action_deadline}
            action_seconds={PokerTable.action_seconds()}
            viewer_user_id={@current_scope.user.id}
            my_seat_taken?={not is_nil(my_seat(@state, @current_scope.user.id))}
          />

          <.bet_chips
            :for={{seat_index, amount} <- active_bets(@state.hand)}
            id={"bet-chips-#{seat_index}"}
            position={bet_chip_position(seat_index)}
            amount={amount}
          />
        </div>

        <div class="relative z-10 mt-8 flex flex-col items-center gap-3">
          <button
            :if={my_seat(@state, @current_scope.user.id)}
            id="leave-table-button"
            type="button"
            phx-click="leave_table"
            class="btn btn-outline btn-sm"
          >
            Leave table
          </button>
        </div>
      </div>

      <div
        :if={@my_turn?}
        id="action-bar-footer"
        class="fixed inset-x-0 bottom-0 z-20 border-t border-base-300 bg-base-100/95 px-4 py-3 shadow-[0_-6px_16px_rgba(0,0,0,0.25)] backdrop-blur"
      >
        <div class="mx-auto max-w-4xl">
          <.action_bar state={@state} my_seat={my_seat(@state, @current_scope.user.id)} />
        </div>
      </div>

      <.join_modal
        :if={@join_seat}
        seat_index={@join_seat}
        table={@table}
        balance={@current_scope.user.balance}
        amount={@buy_in_amount}
        error={@action_error}
      />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ActionTimer">
        export default {
          mounted() { this.start() },
          updated() { this.start() },
          destroyed() { this.clearTick() },
          start() {
            const deadline = new Date(this.el.dataset.deadline).getTime()
            const remainingMs = Math.max(0, deadline - Date.now())
            this.el.style.transition = "none"
            this.el.style.width = "100%"
            void this.el.offsetWidth
            this.el.style.transition = `width ${remainingMs}ms linear`
            this.el.style.width = "0%"

            // The clock only starts audibly ticking once 5 seconds remain,
            // matching the visible countdown bar - scheduled from here
            // (rather than the server) so it stays exact regardless of
            // render/network latency.
            this.clearTick()
            const tickInMs = remainingMs - 5000
            if (tickInMs <= 0) {
              this.playTick(remainingMs)
            } else {
              this.tickTimer = setTimeout(() => this.playTick(5000), tickInMs)
            }
          },
          // `maxMs` cuts the clip off at the 5-second mark even though
          // it's actually ~7s long, and also caps it at whatever's left
          // on the clock if the bar mounts with under 5s remaining.
          playTick(maxMs) {
            this.stopTick()
            if (localStorage.getItem("high_society:sound_muted") === "true") return

            this.tickAudio = new Audio("/audio/clock-ticking.aac")
            this.tickAudio.volume = 0.35
            this.tickAudio.play().catch(() => {})
            this.tickStopTimer = setTimeout(() => this.stopTick(), maxMs)
          },
          // Cancels a still-pending tick, and stops one already playing -
          // called whenever the bar re-renders for a new turn, and when
          // it's removed outright (the player acted before the clip
          // started, or before it would have naturally finished).
          clearTick() {
            if (this.tickTimer) clearTimeout(this.tickTimer)
            this.stopTick()
          },
          stopTick() {
            if (this.tickStopTimer) clearTimeout(this.tickStopTimer)
            if (this.tickAudio) {
              this.tickAudio.pause()
              this.tickAudio.currentTime = 0
              this.tickAudio = null
            }
          }
        }
      </script>

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
            // Only "bet"/"call" (both -> poker-bet.aac) have a recorded
            // clip; check/fold/raise/all-in are synthesized on the fly
            // via Web Audio, since no clip exists for them yet.
            this.fileSrc = {
              bet: "/audio/poker-bet.aac"
            }
            this.synth = {
              check: () => this.playCheck(),
              fold: () => this.playFold(),
              raise: () => this.playRaise(),
              "all-in": () => this.playAllIn()
            }

            this.handleEvent("play_sound", ({sound}) => {
              if (this.muted()) return

              if (this.synth[sound]) {
                this.synth[sound]()
                return
              }

              const src = this.fileSrc[sound] || `/audio/${sound}.aac`
              new Audio(src).play().catch(() => {})
            })
          },
          muted() {
            return localStorage.getItem("high_society:sound_muted") === "true"
          },
          // Lazily created (and resumed) on first use, per the Web Audio
          // autoplay policy - a fresh AudioContext starts suspended until
          // a user gesture, and this hook only ever plays in response to
          // one (a click that led to a server round-trip).
          ctx() {
            if (!this.audioCtx) this.audioCtx = new (window.AudioContext || window.webkitAudioContext)()
            if (this.audioCtx.state === "suspended") this.audioCtx.resume()
            return this.audioCtx
          },
          // Neutral, warm double wood-tap.
          playCheck() {
            const ctx = this.ctx()
            const now = ctx.currentTime

            const tap = (time) => {
              const osc = ctx.createOscillator()
              const gain = ctx.createGain()

              osc.type = "triangle"
              osc.frequency.setValueAtTime(180, time)

              gain.gain.setValueAtTime(0.4, time)
              gain.gain.exponentialRampToValueAtTime(0.001, time + 0.08)

              osc.connect(gain)
              gain.connect(ctx.destination)

              osc.start(time)
              osc.stop(time + 0.08)
            }

            tap(now)
            tap(now + 0.12)
          },
          // Soft friction card-slide, from filtered white noise.
          playFold() {
            const ctx = this.ctx()
            const now = ctx.currentTime
            const duration = 0.15

            const buffer = ctx.createBuffer(1, ctx.sampleRate * duration, ctx.sampleRate)
            const data = buffer.getChannelData(0)
            for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1

            const noise = ctx.createBufferSource()
            noise.buffer = buffer

            const filter = ctx.createBiquadFilter()
            filter.type = "bandpass"
            filter.frequency.setValueAtTime(1200, now)
            filter.frequency.exponentialRampToValueAtTime(400, now + duration)

            const gain = ctx.createGain()
            gain.gain.setValueAtTime(0.15, now)
            gain.gain.exponentialRampToValueAtTime(0.001, now + duration)

            noise.connect(filter)
            filter.connect(gain)
            gain.connect(ctx.destination)

            noise.start(now)
            noise.stop(now + duration)
          },
          // Crisp, ascending chip-drop tone.
          playRaise() {
            const ctx = this.ctx()
            const now = ctx.currentTime

            const osc = ctx.createOscillator()
            const gain = ctx.createGain()
            const filter = ctx.createBiquadFilter()

            osc.type = "sine"
            osc.frequency.setValueAtTime(550, now)
            osc.frequency.exponentialRampToValueAtTime(750, now + 0.15)

            filter.type = "lowpass"
            filter.frequency.setValueAtTime(1500, now)

            gain.gain.setValueAtTime(0.3, now)
            gain.gain.exponentialRampToValueAtTime(0.001, now + 0.18)

            osc.connect(filter)
            filter.connect(gain)
            gain.connect(ctx.destination)

            osc.start(now)
            osc.stop(now + 0.18)
          },
          // Deep thud plus a brief high chime, for finality.
          playAllIn() {
            const ctx = this.ctx()
            const now = ctx.currentTime

            const bassOsc = ctx.createOscillator()
            const bassGain = ctx.createGain()
            bassOsc.type = "triangle"
            bassOsc.frequency.setValueAtTime(90, now)
            bassOsc.frequency.exponentialRampToValueAtTime(40, now + 0.4)
            bassGain.gain.setValueAtTime(0.6, now)
            bassGain.gain.exponentialRampToValueAtTime(0.001, now + 0.4)
            bassOsc.connect(bassGain)
            bassGain.connect(ctx.destination)

            const chimeOsc = ctx.createOscillator()
            const chimeGain = ctx.createGain()
            chimeOsc.type = "sine"
            chimeOsc.frequency.setValueAtTime(2200, now)
            chimeGain.gain.setValueAtTime(0.08, now)
            chimeGain.gain.exponentialRampToValueAtTime(0.001, now + 0.6)
            chimeOsc.connect(chimeGain)
            chimeGain.connect(ctx.destination)

            bassOsc.start(now)
            chimeOsc.start(now)
            bassOsc.stop(now + 0.4)
            chimeOsc.stop(now + 0.6)
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".InlineStyle">
        export default {
          mounted() { this.el.style.cssText = this.el.dataset.style },
          updated() { this.el.style.cssText = this.el.dataset.style }
        }
      </script>
    </Layouts.app>
    """
  end

  attr :seat_index, :integer, required: true
  attr :position, :map, required: true
  attr :seat, :map, default: nil
  attr :hand, :map, default: nil
  attr :button_seat, :integer, default: nil
  attr :action_deadline, :any, default: nil
  attr :action_seconds, :integer, required: true
  attr :viewer_user_id, :integer, required: true
  attr :my_seat_taken?, :boolean, required: true

  defp seat(%{seat: nil} = assigns) do
    ~H"""
    <div
      id={"seat-#{@seat_index}"}
      class="absolute flex w-28 -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1"
      phx-hook=".InlineStyle"
      data-style={"top: #{@position.top}%; left: #{@position.left}%;"}
    >
      <button
        :if={!@my_seat_taken?}
        type="button"
        phx-click="open_join"
        phx-value-seat={@seat_index}
        class="btn btn-outline btn-xs rounded-full border-dashed"
      >
        Join
      </button>
      <div
        :if={@my_seat_taken?}
        class="rounded-full border border-dashed border-white/20 px-3 py-1 text-xs text-white/30"
      >
        Empty
      </div>
    </div>
    """
  end

  defp seat(assigns) do
    hand_seat = assigns.hand && Map.get(assigns.hand.seats, assigns.seat_index)

    acting? =
      assigns.hand && assigns.hand.status == :in_progress &&
        assigns.hand.action_on == assigns.seat_index

    folded? = hand_seat && hand_seat.status == :folded

    assigns =
      assigns
      |> assign(:hand_seat, hand_seat)
      |> assign(:acting?, acting?)
      |> assign(:folded?, folded?)
      |> assign(:mine?, assigns.seat.user_id == assigns.viewer_user_id)
      |> assign(
        :reveal?,
        reveal_hole_cards?(
          hand_seat,
          assigns.seat.user_id == assigns.viewer_user_id,
          assigns.hand
        )
      )

    ~H"""
    <div
      id={"seat-#{@seat_index}"}
      class={[
        "absolute flex w-56 -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1 rounded-xl p-2 transition-opacity",
        @acting? && "bg-amber-400/10 ring-2 ring-amber-400",
        @folded? && "opacity-40"
      ]}
      phx-hook=".InlineStyle"
      data-style={"top: #{@position.top}%; left: #{@position.left}%;"}
    >
      <div class="flex items-center gap-1 text-xs font-semibold text-white">
        <span
          :if={@button_seat == @seat_index}
          class="flex size-4 items-center justify-center rounded-full bg-white text-[10px] font-bold text-black"
        >
          D
        </span>
        <span class="truncate">{@seat.username}</span>
      </div>
      <div class="text-[11px] text-amber-200">${format_money(current_stack(@seat, @hand_seat))}</div>

      <div :if={@hand_seat} class="flex w-40 gap-2">
        <.card_face :for={card <- @hand_seat.hole_cards} card={card} face_down={not @reveal?} />
      </div>

      <div
        :if={@acting?}
        id={"action-timer-#{@seat_index}"}
        class="h-1 w-full overflow-hidden rounded-full bg-black/40"
      >
        <div
          :if={@action_deadline}
          class="h-full bg-amber-400"
          phx-hook=".ActionTimer"
          id={"action-timer-bar-#{@seat_index}"}
          data-deadline={DateTime.to_iso8601(@action_deadline)}
        />
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :position, :map, required: true
  attr :amount, :integer, required: true

  # A seat's current-street bet, sitting partway between their seat and the
  # pot - it disappears (and the pot total grows) the moment the street
  # closes and `contributed_this_street` resets to 0, which reads as the
  # bet being swept into the pot without needing any explicit animation.
  defp bet_chips(assigns) do
    ~H"""
    <div
      id={@id}
      class="absolute flex -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1"
      phx-hook=".InlineStyle"
      data-style={"top: #{@position.top}%; left: #{@position.left}%;"}
    >
      <.chip_stack id={"#{@id}-stack"} amount={@amount} chip_size="size-5" />
      <span class="rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-semibold text-white">
        ${format_money(@amount)}
      </span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :amount, :integer, required: true
  attr :chip_size, :string, required: true

  # A small stack of casino chips, colored and counted (1-3) by how large
  # `amount` is - a stand-in for a real denomination breakdown, since a
  # poker bet is rarely made of neat, individually-tracked chip values.
  defp chip_stack(assigns) do
    ~H"""
    <div class="relative flex h-8 w-8 items-end justify-center">
      <div
        :for={i <- 0..(chip_count(@amount) - 1)}
        id={"#{@id}-chip-#{i}"}
        class={[
          "absolute rounded-full border-2 border-dashed shadow",
          @chip_size,
          chip_tier_color(@amount)
        ]}
        phx-hook=".InlineStyle"
        data-style={"bottom: #{i * 4}px;"}
      />
    </div>
    """
  end

  defp chip_count(amount) when amount >= 100, do: 3
  defp chip_count(amount) when amount >= 25, do: 2
  defp chip_count(_amount), do: 1

  defp chip_tier_color(amount) when amount >= 100, do: "border-amber-300 bg-amber-500"
  defp chip_tier_color(amount) when amount >= 25, do: "border-neutral-600 bg-neutral-900"
  defp chip_tier_color(amount) when amount >= 5, do: "border-red-300 bg-red-600"
  defp chip_tier_color(_amount), do: "border-neutral-400 bg-neutral-100"

  attr :state, :map, required: true
  attr :my_seat, :integer, required: true

  defp action_bar(assigns) do
    hand = assigns.state.hand
    my = hand.seats[assigns.my_seat]
    to_call = min(hand.current_bet - my.contributed_this_street, my.stack)
    max_amount = my.stack + my.contributed_this_street
    min_bet = min(hand.big_blind, max_amount)
    min_raise_to = min(hand.current_bet + hand.min_raise, max_amount)

    assigns =
      assigns
      |> assign(:to_call, to_call)
      |> assign(:max_amount, max_amount)
      |> assign(:min_amount, if(hand.current_bet == 0, do: min_bet, else: min_raise_to))
      |> assign(:can_check?, my.contributed_this_street == hand.current_bet)
      |> assign(:can_raise_or_bet?, my.stack > to_call)
      |> assign(:bet_label, if(hand.current_bet == 0, do: "Bet", else: "Raise to"))

    ~H"""
    <div
      id="action-bar"
      class="flex flex-col items-center gap-3 rounded-2xl border border-base-300 bg-base-200 p-4"
    >
      <div class="flex gap-2">
        <button
          id="fold-button"
          type="button"
          phx-click="act"
          phx-value-action="fold"
          class="btn btn-sm border-none bg-red-700 text-white hover:bg-red-600"
        >
          Fold
        </button>
        <button
          :if={@can_check?}
          id="check-button"
          type="button"
          phx-click="act"
          phx-value-action="check"
          class="btn btn-sm border-none bg-neutral-600 text-white hover:bg-neutral-500"
        >
          Check
        </button>
        <button
          :if={!@can_check?}
          id="call-button"
          type="button"
          phx-click="act"
          phx-value-action="call"
          class="btn btn-sm border-none bg-emerald-600 text-white hover:bg-emerald-500"
        >
          Call ${format_money(@to_call)}
        </button>
      </div>

      <form :if={@can_raise_or_bet?} phx-submit="bet_or_raise" class="flex items-center gap-2">
        <input
          type="range"
          name="amount"
          min={@min_amount}
          max={@max_amount}
          value={@min_amount}
          id="bet-amount-slider"
          phx-hook=".BetSlider"
          class="range range-sm w-48"
        />
        <output id="bet-amount-output" class="w-16 text-right text-sm font-semibold">${format_money(
          @min_amount
        )}</output>
        <button
          type="submit"
          id="bet-raise-button"
          class="btn btn-sm border-none bg-indigo-600 text-white hover:bg-indigo-500"
        >
          {@bet_label}
        </button>
      </form>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".BetSlider">
      export default {
        mounted() {
          this.output = this.el.parentElement.querySelector("output")
          this.el.addEventListener("input", () => {
            this.output.textContent = "$" + Number(this.el.value).toLocaleString("en-US")
          })
        }
      }
    </script>
    """
  end

  attr :seat_index, :integer, required: true
  attr :table, :map, required: true
  attr :balance, :integer, required: true
  attr :amount, :integer, required: true
  attr :error, :string, default: nil

  defp join_modal(assigns) do
    min_buy_in = PokerTables.min_buy_in(assigns.table)
    max_buy_in = min(PokerTables.max_buy_in(assigns.table), assigns.balance)

    assigns = assigns |> assign(:min_buy_in, min_buy_in) |> assign(:max_buy_in, max_buy_in)

    ~H"""
    <div id="join-modal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div class="w-full max-w-sm rounded-2xl bg-base-100 p-6 shadow-xl">
        <h2 class="text-lg font-bold">Buy in for seat {@seat_index + 1}</h2>
        <p class="mt-1 text-sm text-base-content/60">
          Between ${format_money(@min_buy_in)} and ${format_money(@max_buy_in)}.
        </p>

        <p :if={@error} id="join-error" class="mt-3 text-sm font-medium text-error">{@error}</p>

        <%= if @max_buy_in >= @min_buy_in do %>
          <form phx-submit="confirm_join" class="mt-4 flex flex-col items-center gap-2">
            <input
              type="range"
              name="amount"
              min={@min_buy_in}
              max={@max_buy_in}
              value={@amount}
              id="buy-in-slider"
              phx-change="set_buy_in"
              class="range range-sm w-full"
            />
            <div id="buy-in-amount" class="text-2xl font-bold">${format_money(@amount)}</div>
            <div class="mt-2 flex gap-2">
              <button type="button" phx-click="close_join" class="btn btn-ghost btn-sm">Cancel</button>
              <button type="submit" id="confirm-join-button" class="btn btn-primary btn-sm">Sit down</button>
            </div>
          </form>
        <% else %>
          <p class="mt-4 text-sm text-error">
            You don't have enough chips for this table's minimum buy-in.
          </p>
          <button type="button" phx-click="close_join" class="btn btn-ghost btn-sm mt-4">Close</button>
        <% end %>
      </div>
    </div>
    """
  end

  defp seat_position(seat_index), do: Enum.at(@seat_positions, seat_index)

  # Midway between the seat and the felt's center - far enough from the
  # (fairly wide) seat marker to read as its own thing, short of actually
  # sitting in the pot.
  defp bet_chip_position(seat_index) do
    seat = seat_position(seat_index)
    %{top: along(seat.top, @center.top), left: along(seat.left, @center.left)}
  end

  defp along(from, to), do: from + (to - from) * 0.5

  defp active_bets(nil), do: []

  defp active_bets(%Poker{seats: seats}) do
    seats
    |> Enum.filter(fn {_i, s} -> s.contributed_this_street > 0 end)
    |> Enum.map(fn {i, s} -> {i, s.contributed_this_street} end)
  end

  defp my_seat(state, user_id) do
    case Enum.find(state.seats, fn {_i, s} -> s.user_id == user_id end) do
      nil -> nil
      {seat_index, _seat} -> seat_index
    end
  end

  defp my_turn?(%{hand: nil}, _user_id), do: false

  defp my_turn?(state, user_id) do
    state.hand.status == :in_progress && state.hand.action_on == my_seat(state, user_id)
  end

  defp reveal_hole_cards?(nil, _mine?, _hand), do: false
  defp reveal_hole_cards?(_hand_seat, true, _hand), do: true

  defp reveal_hole_cards?(hand_seat, false, hand),
    do: hand.status == :hand_over and hand_seat.status != :folded

  defp current_stack(seat, nil), do: seat.stack
  defp current_stack(_seat, hand_seat), do: hand_seat.stack

  defp community_cards(nil), do: []
  defp community_cards(%Poker{community_cards: cards}), do: cards

  defp community_card_slots(hand) do
    cards = community_cards(hand)
    cards ++ List.duplicate(nil, 5 - length(cards))
  end

  defp pot_total(nil), do: 0

  defp pot_total(%Poker{pots: nil, seats: seats}),
    do: seats |> Map.values() |> Enum.map(& &1.total_contributed) |> Enum.sum()

  defp pot_total(%Poker{pots: pots}), do: pots |> Enum.map(& &1.amount) |> Enum.sum()

  # While a hand is live, the pot sits at the felt's center. Once it's
  # over, it slides to whichever single seat won everything - a split pot
  # (more than one distinct winning seat, whether from one pot split
  # multiple ways or separate side pots going to different seats) has no
  # single destination to animate toward, so it just stays put and lets
  # the winner banner's text explain it instead.
  defp pot_chip_position(hand) do
    case winning_seats(hand) do
      [seat] -> seat_position(seat)
      _ -> @center
    end
  end

  defp winning_seats(%Poker{status: :hand_over, pots: pots}),
    do: pots |> Enum.flat_map(& &1.winners) |> Enum.uniq()

  defp winning_seats(_hand), do: []

  # The showdown/uncontested-win callout: one clause per pot (almost
  # always just one), each naming its winner(s), the amount they took,
  # and - only when a real showdown happened for that pot (more than one
  # seat was still eligible for it, and all five community cards are out)
  # rather than everyone else simply folding - the winning hand's
  # category, e.g. "Flush".
  defp winner_text(%Poker{status: :hand_over} = hand),
    do: hand.pots |> Enum.map(&pot_summary(&1, hand)) |> Enum.join("  •  ")

  defp winner_text(_hand), do: nil

  defp pot_summary(pot, hand) do
    names = pot.winners |> Enum.map(&Map.fetch!(hand.seats, &1).username) |> Enum.join(" & ")
    plural = if length(pot.winners) == 1, do: "s", else: ""
    suffix = if name = showdown_hand_name(pot, hand), do: " with a #{name}", else: ""
    "#{names} win#{plural} $#{format_money(pot.amount)}#{suffix}"
  end

  defp showdown_hand_name(%{eligible: eligible, winners: [seat | _]}, hand)
       when length(eligible) > 1 do
    case hand.community_cards do
      community when length(community) == 5 ->
        hand.seats
        |> Map.fetch!(seat)
        |> Map.fetch!(:hole_cards)
        |> Kernel.++(community)
        |> HandEvaluator.rank()
        |> HandEvaluator.category_name()

      _ ->
        nil
    end
  end

  defp showdown_hand_name(_pot, _hand), do: nil

  defp format_money(amount) when is_integer(amount) do
    amount
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
