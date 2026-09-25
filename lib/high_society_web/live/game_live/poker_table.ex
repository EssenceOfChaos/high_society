defmodule HighSocietyWeb.GameLive.PokerTable do
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games.Poker
  alias HighSociety.Games.Poker.HandEvaluator
  alias HighSociety.Games.PokerTable
  alias HighSociety.Games.PokerTables
  alias HighSociety.Tokens
  alias HighSocietyWeb.Presence

  # Screen slots for up to 8 seats, arranged clockwise around the felt
  # starting at bottom-center (index 0). Which raw seat_index lands in
  # which slot is rotated per viewer by `display_seat_index/2` so every
  # seated player sees themselves in the conventional "you're at the
  # bottom" spot, with the rest of the table following clockwise from
  # them - not a single fixed layout everyone shares.
  #
  # The left/right-most slots (2 and 6) sit at 6%/94%, not flush with the
  # felt's own edge - a seat card is centered on its position (a
  # `-translate-x-1/2`), so anything much closer to 0%/100% here has its
  # own half-width overhang past the felt entirely, clipped by the
  # viewport with no scrollbar to reach it, on anything narrower than a
  # very wide desktop window (see `#poker-table-screen`'s own side
  # padding, sized to cover the rest of this same overhang).
  #
  # Those same two slots also sit at `top: 48`, i.e. squarely inside the
  # community card row's own vertical band (see `@pot_position`'s doc
  # comment) - fine on a wide desktop felt, where there's enough
  # horizontal room between a side seat and the centered community cards
  # for neither to touch the other, but on a narrow phone-width felt the
  # two collide, burying a side seat's hole cards behind the community
  # cards. `seat_top_class/1` below carries a `max-sm:` override to lift
  # just those two slots clear of that band on narrow viewports, leaving
  # the tablet/desktop position (where there's no collision) untouched.
  @seat_positions [
    %{top: 94, left: 50},
    %{top: 80, left: 90},
    %{top: 48, left: 94},
    %{top: 12, left: 88},
    %{top: 0, left: 50},
    %{top: 12, left: 12},
    %{top: 48, left: 6},
    %{top: 80, left: 10}
  ]

  # The felt's geometric center - used only to place each seat's bet chips
  # partway between that seat and the middle of the table, never as the
  # pot's own resting spot (see `@pot_position`), since that's exactly
  # where the community cards sit too.
  @center %{top: 50, left: 50}

  # Where the pot itself rests while a hand's live - above the community
  # card row (which runs roughly 38%-62% of the felt's height) rather than
  # dead center, so the two never overlap.
  @pot_position %{top: 20, left: 50}

  # Static reference content for the hand-rankings modal (`hand_rankings_modal/1`)
  # - best hand first, worst last - each with an example 5-card hand
  # illustrating it. Purely educational display data, unrelated to
  # `HandEvaluator`'s own category numbering (which doesn't distinguish a
  # royal flush from any other ace-high straight flush). `kickers` holds the
  # 0-based indexes into `cards` that aren't actually part of the named
  # combination, so the modal can render them dimmed.
  @hand_rankings [
    %{
      name: "Royal Flush",
      cards: ~w(AS KS QS JS 10S),
      kickers: [],
      description: "An ace-high straight flush - the best possible hand."
    },
    %{
      name: "Straight Flush",
      cards: ~w(9H 8H 7H 6H 5H),
      kickers: [],
      description: "Five consecutive cards, all the same suit."
    },
    %{
      name: "Four of a Kind",
      cards: ~w(9S 9H 9D 9C 2H),
      kickers: [4],
      description: "Four cards of the same rank."
    },
    %{
      name: "Full House",
      cards: ~w(KS KH KD 4C 4S),
      kickers: [],
      description: "Three cards of one rank plus two of another."
    },
    %{
      name: "Flush",
      cards: ~w(AS JS 8S 5S 2S),
      kickers: [],
      description: "Five cards of the same suit, in any order."
    },
    %{
      name: "Straight",
      cards: ~w(9C 8H 7S 6D 5C),
      kickers: [],
      description: "Five consecutive cards of different suits."
    },
    %{
      name: "Three of a Kind",
      cards: ~w(7H 7S 7D KC 4H),
      kickers: [3, 4],
      description: "Three cards of the same rank."
    },
    %{
      name: "Two Pair",
      cards: ~w(AS AH KD KC 2S),
      kickers: [4],
      description: "Two cards of one rank and two of another."
    },
    %{
      name: "Pair",
      cards: ~w(JS JH 8D 6C 2H),
      kickers: [2, 3, 4],
      description: "Two cards of the same rank."
    },
    %{
      name: "High Card",
      cards: ~w(QS JH 8D 6C 3H),
      kickers: [1, 2, 3, 4],
      description: "No combination - the highest card plays."
    }
  ]

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
            page_title: "Poker – #{table_config.name}",
            slug: slug,
            table: table_config,
            state: state,
            viewer_count: viewer_count,
            join_seat: nil,
            buy_in_amount: nil,
            action_error: nil,
            hand_rankings_open?: false,
            settings_open?: false
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

  def handle_event("open_hand_rankings", _params, socket),
    do: {:noreply, assign(socket, :hand_rankings_open?, true)}

  def handle_event("close_hand_rankings", _params, socket),
    do: {:noreply, assign(socket, :hand_rankings_open?, false)}

  def handle_event("open_settings", _params, socket),
    do: {:noreply, assign(socket, :settings_open?, true)}

  def handle_event("close_settings", _params, socket),
    do: {:noreply, assign(socket, :settings_open?, false)}

  # `choice`, not `value` - a plain `<button>`'s native `.value` DOM
  # property (empty string, absent any `value=` attribute) rides along in
  # every click payload under the key `"value"` regardless of any custom
  # `phx-value-*`, so a custom param actually named `value` gets silently
  # overwritten with `""` by the time `handle_event` sees it.
  def handle_event("set_card_back", %{"choice" => choice}, socket),
    do: update_poker_settings(socket, %{card_back: choice})

  def handle_event("set_felt_color", %{"choice" => choice}, socket),
    do: update_poker_settings(socket, %{felt_color: choice})

  # A second click on the already-active option clears it back to "neither
  # selected" rather than being a no-op, since that's the only way to
  # reach that state again once one's been chosen.
  def handle_event("set_muck_preference", %{"choice" => choice}, socket) do
    current = socket.assigns.current_scope.user.muck_preference

    update_poker_settings(socket, %{muck_preference: if(current == choice, do: nil, else: choice)})
  end

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

  def handle_event("reveal_hand", _params, socket) do
    user = socket.assigns.current_scope.user

    case PokerTable.reveal_hand(socket.assigns.slug, user.id) do
      {:ok, view} -> {:noreply, assign(socket, :state, view)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("claim_poker_tokens", _params, socket) do
    case Accounts.claim_poker_tokens(socket.assigns.current_scope.user) do
      {:ok, user} -> {:noreply, assign(socket, current_scope: Scope.for_user(user))}
      {:error, :already_claimed} -> {:noreply, socket}
    end
  end

  defp update_poker_settings(socket, attrs) do
    case Accounts.update_poker_settings(socket.assigns.current_scope.user, attrs) do
      {:ok, user} -> {:noreply, assign(socket, current_scope: Scope.for_user(user))}
      {:error, _changeset} -> {:noreply, socket}
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

  defp join_error_message(:insufficient_funds),
    do: "You don't have enough Tokens for that buy-in."

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
  defp action_error_message(:exceeds_stack), do: "You don't have that many Tokens."
  defp action_error_message(_reason), do: "Couldn't complete that action."

  @impl true
  def render(assigns) do
    my_seat_index = my_seat(assigns.state, assigns.current_scope.user.id)

    assigns =
      assigns
      |> assign(:my_turn?, my_turn?(assigns.state, assigns.current_scope.user.id))
      |> assign(:my_seat_index, my_seat_index)
      |> assign(:view_anchor_seat, my_seat_index)
      |> assign(:card_back_image, card_back_image(assigns.current_scope.user.card_back))
      |> assign(:felt_gradient_class, felt_gradient_class(assigns.current_scope.user.felt_color))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="poker-table-screen"
        class={["mx-auto max-w-4xl", @my_turn? && "pb-20"]}
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
              Blinds {Tokens.format(@table.small_blind)} / {Tokens.format(@table.big_blind)} Tokens &middot;
              <.icon name="hero-eye" class="-mt-0.5 inline size-4" /> {@viewer_count} watching
            </p>
            <button
              :if={my_seat(@state, @current_scope.user.id)}
              id="leave-table-button"
              type="button"
              phx-click="leave_table"
              class="btn btn-outline btn-sm mt-2"
            >
              Leave table
            </button>
          </div>
          <div class="flex items-center gap-3">
            <div class="text-right">
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/50">
                Balance
              </div>
              <.token_balance amount={@current_scope.user.tokens_balance} />
            </div>
            <button
              :if={is_nil(@current_scope.user.claimed_poker_tokens_at)}
              id="claim-poker-tokens-button"
              type="button"
              phx-click="claim_poker_tokens"
              class="btn btn-success btn-sm animate-pulse"
            >
              Claim {Tokens.format(Accounts.poker_starting_token_amount())} Tokens
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
            <button
              id="settings-button"
              type="button"
              phx-click="open_settings"
              class="btn btn-ghost btn-sm btn-circle tooltip tooltip-bottom"
              aria-label="Table settings"
              data-tip="Settings"
            >
              <.icon name="hero-cog-6-tooth" class="size-5" />
            </button>
            <button
              id="hand-rankings-button"
              type="button"
              phx-click="open_hand_rankings"
              class="btn btn-ghost btn-sm btn-circle tooltip tooltip-bottom"
              aria-label="Poker hand rankings"
              data-tip="Hand Rankings"
            >
              <.icon name="hero-question-mark-circle" class="size-5" />
            </button>
            <.link
              navigate={~p"/games/poker/leaderboard"}
              class="btn btn-ghost btn-sm btn-circle tooltip tooltip-bottom"
              aria-label="Leaderboard"
              data-tip="Leaderboard"
            >
              <.icon name="hero-trophy" class="size-5" />
            </.link>
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
          class={[
            "relative mx-8 mt-6 min-h-[26rem] rounded-3xl bg-gradient-to-b shadow-xl ring-1 ring-black/40 sm:mx-10 lg:aspect-[7/5] lg:min-h-0",
            @felt_gradient_class
          ]}
        >
          <div class="absolute left-1/2 top-1/2 flex w-max -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-2">
            <div id="community-cards" class="flex gap-1 lg:gap-2">
              <.card_face
                :for={{card, index} <- Enum.with_index(community_card_slots(@state.hand))}
                id={"community-card-#{index}"}
                card={card}
                card_back={@card_back_image}
                deal_animation
              />
            </div>
          </div>

          <p
            :if={@state.hand && @state.hand.status == :hand_over}
            id="winner-banner"
            class="absolute inset-x-0 top-3 z-30 mx-auto w-fit animate-bounce rounded-full bg-black/80 px-4 py-1 text-center text-sm font-bold text-amber-300 shadow-lg [animation-iteration-count:2]"
          >
            {winner_text(@state.hand)}
          </p>

          <%!-- z-40, above the winner banner's z-30 and every `.seat`
          (unindexed, and rendered later in the DOM, so they'd otherwise
          win the default stacking order) - `.ChipFlight`'s payout
          animation flies this well past its resting spot to pause right
          on top of the winning seat, and without an explicit z-index it
          would land half-hidden behind that seat's own cards during
          exactly the moment it's supposed to be the thing to look at. --%>
          <div
            :if={pot_total(@state.hand) > 0}
            id="pot-chips"
            class="absolute left-[50%] top-[20%] z-40 -translate-x-1/2 -translate-y-1/2"
          >
            <div
              id="pot-chips-flight"
              class="flex flex-col items-center gap-1"
              phx-hook=".ChipFlight"
              data-flight-key={pot_total(@state.hand)}
              data-exit-key={payout_flight_key(@state.hand)}
              data-exit-dx-percent={payout_offset(@state.hand, @view_anchor_seat).dx}
              data-exit-dy-percent={payout_offset(@state.hand, @view_anchor_seat).dy}
            >
              <.chip_stack id="pot-chips-stack" amount={pot_total(@state.hand)} chip_size="size-7" />
              <div class="rounded-full bg-black/50 px-4 py-1 text-sm font-semibold text-amber-200">
                Pot: {Tokens.format(pot_total(@state.hand))} Tokens
              </div>
            </div>
          </div>

          <.seat
            :for={seat_index <- 0..(PokerTables.seats() - 1)}
            seat_index={seat_index}
            position={seat_position(seat_index, @view_anchor_seat)}
            seat={Map.get(@state.seats, seat_index)}
            hand={@state.hand}
            button_seat={@state.button_seat}
            action_deadline={@state.action_deadline}
            action_seconds={PokerTable.action_seconds()}
            viewer_user_id={@current_scope.user.id}
            viewer_muck_preference={@current_scope.user.muck_preference}
            card_back={@card_back_image}
            my_seat_taken?={not is_nil(@my_seat_index)}
          />

          <.bet_chips
            :for={{seat_index, amount} <- active_bets(@state.hand)}
            id={"bet-chips-#{seat_index}"}
            position={bet_chip_position(seat_index, @view_anchor_seat)}
            from_position={seat_position(seat_index, @view_anchor_seat)}
            amount={amount}
          />
        </div>
      </div>

      <div
        :if={@my_turn?}
        id="action-bar-footer"
        class="fixed inset-x-0 bottom-0 z-20 w-full border-t border-base-300 bg-base-100/95 px-4 py-4 shadow-[0_-6px_16px_rgba(0,0,0,0.25)] backdrop-blur"
      >
        <.action_bar state={@state} my_seat={my_seat(@state, @current_scope.user.id)} />
      </div>

      <.join_modal
        :if={@join_seat}
        seat_index={@join_seat}
        table={@table}
        tokens_balance={@current_scope.user.tokens_balance}
        amount={@buy_in_amount}
        error={@action_error}
      />

      <.hand_rankings_modal :if={@hand_rankings_open?} />

      <.settings_modal :if={@settings_open?} user={@current_scope.user} />

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

            this.tickAudio = new Audio("/audio/poker/clock-ticking.aac")
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
              bet: "/audio/poker/poker-bet.aac"
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

              const src = this.fileSrc[sound] || `/audio/poker/${sound}.aac`
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

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ChipFlight">
        export default {
          // The *inner* content of a chip stack (a bet, or the pot) -
          // its outer positioning anchor (percentage `top`/`left`) carries
          // the `-translate-x-1/2 -translate-y-1/2` centering, deliberately
          // left untouched here: anime.js only preserves a Tailwind-class-
          // only transform if there's a matching *inline* one for it to
          // track, and starting from nothing but the class, its internal
          // bookkeeping drops that centering the moment it touches the
          // element at all (confirmed empirically - even animating an
          // unrelated property left `transform` stuck at `none`). This
          // element has no transform of its own to lose, so it's the one
          // anime.js is safe to own.
          //
          // Two independent flights, each keyed off its own data attribute
          // so one firing is never gated on the other:
          //   - entry (`data-flight-key`): flies *in* from
          //     `data-dx-percent`/`data-dy-percent` (a bet's offset from
          //     its own seat, in percent of the felt - 0 for the pot,
          //     which has no single seat to fly from) every time the key
          //     changes (the pot growing, a fresh bet) or, lacking a key
          //     at all (a bet chip stack never gets one - the same seat's
          //     stack just grows in place), once on first mount.
          //   - exit (`data-exit-key`, only ever set on the pot's own
          //     stack): the payout - flies *out* toward
          //     `data-exit-dx-percent`/`data-exit-dy-percent` (the winning
          //     seat's own anchor) and shrinks/fades away, the instant the
          //     key first appears. Snaps back to normal the moment the key
          //     disappears again (the next hand starting) so the stack is
          //     ready to fly in fresh rather than staying shrunk and faded
          //     from the last payout.
          //
          // `this.exitKey` starts recorded (not undefined) rather than
          // triggered - a fresh page load can land mid-`hand_over`, already
          // carrying a payout's `data-exit-key` on first mount, and playing
          // the flight then (for a payout that happened before this viewer
          // even connected) would be nonsensical. Recording it without
          // playing still leaves `updated()` able to detect the *next*
          // real change correctly either way - a new payout's key, or nil
          // once the next hand starts - instead of comparing against
          // `undefined` forever and never matching, which left the stack
          // permanently stuck mid-pause, neither flying nor resetting.
          mounted() {
            this.play()
            this.exitKey = this.el.dataset.exitKey
          },
          updated() {
            const key = this.el.dataset.flightKey
            if (key !== undefined && key !== this.flightKey) this.play()
            this.flightKey = key

            const exitKey = this.el.dataset.exitKey
            if (exitKey && exitKey !== this.exitKey) this.playExit()
            else if (!exitKey && this.exitKey) this.reset()
            this.exitKey = exitKey
          },
          pixels(dxAttr, dyAttr) {
            const dxPercent = parseFloat(this.el.dataset[dxAttr] || "0")
            const dyPercent = parseFloat(this.el.dataset[dyAttr] || "0")
            const felt = document.getElementById("poker-felt")
            const rect = felt && felt.getBoundingClientRect()

            return {
              dx: rect ? (dxPercent / 100) * rect.width : 0,
              dy: rect ? (dyPercent / 100) * rect.height : 0
            }
          },
          play() {
            this.flightKey = this.el.dataset.flightKey
            const { dx, dy } = this.pixels("dxPercent", "dyPercent")

            this.el.style.opacity = "0"
            window.animeAnimate(this.el, {
              translateX: [dx, 0],
              translateY: [dy, 0],
              opacity: [0, 1],
              duration: 550,
              ease: "outQuad"
            })
          },
          // A deliberate, unmissable payout, in two chained animate() calls
          // rather than one multi-segment tween - anime.js's per-property
          // step-array syntax (`{ to, duration }` entries), used further up
          // for the coin's rim opacity, turned out not to drive `transform`
          // the same way it drives a plain property like `opacity`: it
          // silently did nothing at all for `translateX`/`translateY`/
          // `scale` in this build (confirmed empirically - no error, the
          // stack just never moved). Chaining through `onComplete` instead
          // sticks to the plain `[from, to]` array form `play()` already
          // uses successfully. First a quick "picking up" bump (grows
          // slightly, like a real stack being swept up off the felt), then
          // the actual flight toward the winner - fully opaque the whole
          // way, so it reads as chips actually *arriving* rather than
          // dissolving en route - then a firm landing (settling back down
          // from the bump's overshoot) held for a beat so the delivery
          // itself registers, and only then a fade once it's plainly
          // already in the winner's stack. `@hand_over_pause_ms` (7s)
          // comfortably covers this whole sequence (about 3.4s end to
          // end) before the next hand could start, but the pending fade
          // still checks `this.exitKey` against the key it was scheduled
          // under before running, in case a hand somehow wraps up early -
          // otherwise a stray fade could fire mid-flight on a *later*
          // payout that happens to reuse this same timer.
          playExit() {
            const exitKey = this.el.dataset.exitKey
            this.exitKey = exitKey
            const { dx, dy } = this.pixels("exitDxPercent", "exitDyPercent")

            window.animeAnimate(this.el, {
              scale: [1, 1.15],
              duration: 220,
              ease: "outQuad",
              onComplete: () => {
                window.animeAnimate(this.el, {
                  translateX: [0, dx],
                  translateY: [0, dy],
                  scale: [1.15, 1],
                  duration: 750,
                  ease: "inQuad",
                  onComplete: () => {
                    setTimeout(() => {
                      if (this.exitKey !== exitKey) return

                      window.animeAnimate(this.el, {
                        opacity: [1, 0],
                        duration: 400,
                        ease: "outQuad"
                      })
                    }, 2000)
                  }
                })
              }
            })
          },
          reset() {
            this.exitKey = undefined
            window.animeAnimate(this.el, {
              translateX: 0,
              translateY: 0,
              scale: 1,
              opacity: 1,
              duration: 1
            })
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SeatFold">
        export default {
          // Tosses a seat's hole cards toward the muck the instant they
          // fold - a quick flick (rotate + drop, settling back to rest)
          // layered on top of the seat's own `transition-opacity` dim,
          // which still does the actual fading. This div has no transform
          // of its own to lose, so - unlike the seat marker itself, which
          // stays untouched - it's safe for anime.js to own outright (see
          // `.ChipFlight` above for why that distinction matters).
          mounted() { this.folded = this.el.dataset.folded === "true" },
          updated() {
            const folded = this.el.dataset.folded === "true"
            if (folded && !this.folded) {
              window.animeAnimate(this.el, {
                rotate: [0, (Math.random() * 16 - 8), 0],
                translateY: [0, 14, 0],
                duration: 420,
                ease: "inOutQuad"
              })
            }
            this.folded = folded
          }
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
  attr :viewer_muck_preference, :string, default: nil
  attr :card_back, :string, required: true
  attr :my_seat_taken?, :boolean, required: true

  defp seat(%{seat: nil} = assigns) do
    ~H"""
    <div
      id={"seat-#{@seat_index}"}
      class={[
        "absolute flex w-28 -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1",
        seat_top_class(@position.top),
        seat_left_class(@position.left)
      ]}
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
    mine? = assigns.seat.user_id == assigns.viewer_user_id

    assigns =
      assigns
      |> assign(:hand_seat, hand_seat)
      |> assign(:acting?, acting?)
      |> assign(:folded?, folded?)
      |> assign(:last_action, !folded? && hand_seat && hand_seat.last_action)
      |> assign(:mine?, mine?)
      |> assign(:reveal?, reveal_hole_cards?(hand_seat, mine?, assigns.hand, assigns.seat_index))
      |> assign(
        :can_reveal?,
        mine? and
          can_reveal?(assigns.hand, assigns.seat_index, assigns.viewer_muck_preference)
      )
      |> assign(
        :category,
        !folded? && mine? && hand_seat && my_hand_category(hand_seat, assigns.hand)
      )

    ~H"""
    <div
      id={"seat-#{@seat_index}"}
      class={[
        "absolute flex -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1 rounded-xl p-2 transition-opacity",
        seat_top_class(@position.top),
        seat_left_class(@position.left),
        @mine? && "w-64 lg:w-80",
        !@mine? && "w-28 sm:w-36 lg:w-56",
        @acting? && "bg-amber-400/10 ring-2 ring-amber-400",
        @folded? && "opacity-40"
      ]}
    >
      <div class="flex items-center gap-1 text-xs font-semibold text-white">
        <span
          :if={@button_seat == @seat_index}
          class="flex size-4 items-center justify-center rounded-full bg-white text-[10px] font-bold text-black"
        >
          D
        </span>
        <span :if={@folded?} class="badge badge-neutral badge-xs font-semibold">
          Folded
        </span>
        <span
          :if={@last_action}
          class={["badge badge-xs font-semibold", action_badge_class(@last_action)]}
        >
          {action_badge_label(@last_action)}
        </span>
        <span class="truncate">{@seat.username}</span>
      </div>
      <div class="text-[11px] text-amber-200">{Tokens.format(current_stack(@seat, @hand_seat))}</div>

      <div :if={@hand_seat} class="indicator">
        <span
          :if={@category}
          class="indicator-item indicator-bottom indicator-center z-20 badge badge-sm border-none bg-amber-400 font-bold text-amber-950 shadow"
        >
          {@category}
        </span>
        <div
          id={"hole-cards-#{@seat_index}"}
          class={[
            "flex justify-center gap-1 lg:gap-2",
            @mine? && "w-60 lg:w-72",
            !@mine? && "w-24 sm:w-32 lg:w-40"
          ]}
          phx-hook=".SeatFold"
          data-folded={to_string(@folded?)}
        >
          <.card_face
            :for={{card, index} <- Enum.with_index(@hand_seat.hole_cards)}
            id={"hole-card-#{@seat_index}-#{index}"}
            card={card}
            face_down={not @reveal?}
            card_back={@card_back}
            size={if @mine?, do: :medium, else: :normal}
            deal_animation
          />
        </div>

        <button
          :if={@can_reveal?}
          id={"reveal-hand-button-#{@seat_index}"}
          type="button"
          phx-click="reveal_hand"
          class="btn btn-sm mt-2 gap-1 rounded-full border-none bg-gradient-to-r from-amber-400 to-amber-500 font-semibold text-amber-950 shadow-md animate-pulse hover:from-amber-300 hover:to-amber-400"
        >
          <.icon name="hero-eye" class="size-4" /> Show my cards
        </button>
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
  attr :from_position, :map, required: true
  attr :amount, :integer, required: true

  # A seat's current-street bet, sitting partway between their seat and the
  # pot. Flies in from the seat itself on first appearance (see
  # `.ChipFlight`) - it still just disappears (and the pot total grows)
  # the moment the street closes and `contributed_this_street` resets to
  # 0, which reads as the bet being swept into the pot without needing an
  # explicit exit animation.
  defp bet_chips(assigns) do
    ~H"""
    <div
      id={@id}
      class="absolute -translate-x-1/2 -translate-y-1/2"
      phx-hook=".InlineStyle"
      data-style={"top: #{@position.top}%; left: #{@position.left}%;"}
    >
      <div
        id={"#{@id}-flight"}
        class="flex flex-col items-center gap-1"
        phx-hook=".ChipFlight"
        data-dx-percent={@from_position.left - @position.left}
        data-dy-percent={@from_position.top - @position.top}
      >
        <.chip_stack id={"#{@id}-stack"} amount={@amount} chip_size="size-5" />
        <span class="rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-semibold text-white">
          {Tokens.format(@amount)}
        </span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :amount, :integer, required: true
  attr :chip_size, :string, required: true

  # A small stack of casino chips, colored and counted (1-5) by how large
  # `amount` is - a stand-in for a real denomination breakdown, since a
  # poker bet is rarely made of neat, individually-tracked chip values.
  # `h-11 w-11` comfortably fits the tallest tier (5 chips at 4px of
  # visible rise each, plus the pot's own `size-7` chip height - the
  # largest combination in play) without clipping; a shorter stack or
  # smaller `chip_size` just leaves empty space above it.
  defp chip_stack(assigns) do
    ~H"""
    <div class="relative flex h-11 w-11 items-end justify-center">
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

  defp chip_count(amount) when amount >= 30_000, do: 5
  defp chip_count(amount) when amount >= 8_000, do: 4
  defp chip_count(amount) when amount >= 2_000, do: 3
  defp chip_count(amount) when amount >= 400, do: 2
  defp chip_count(_amount), do: 1

  defp chip_tier_color(amount) when amount >= 30_000, do: "border-purple-300 bg-purple-600"
  defp chip_tier_color(amount) when amount >= 8_000, do: "border-amber-300 bg-amber-500"
  defp chip_tier_color(amount) when amount >= 2_000, do: "border-neutral-600 bg-neutral-900"
  defp chip_tier_color(amount) when amount >= 400, do: "border-red-300 bg-red-600"
  defp chip_tier_color(_amount), do: "border-neutral-400 bg-neutral-100"

  # A seat's most recent action this street (cleared once the street
  # closes - see `Poker.deal_next_street/3`), badged next to their name so
  # the table reads at a glance without waiting for everyone's turn to
  # come back around. Distinct colors from `Folded`'s neutral gray, and
  # from each other - passive (check) reads cooler/quieter than putting
  # chips in (call), which reads cooler than the aggressive actions.
  defp action_badge_class(:check), do: "badge-ghost"
  defp action_badge_class(:call), do: "badge-info"
  defp action_badge_class(:bet), do: "badge-warning"
  defp action_badge_class(:raise), do: "badge-warning"

  defp action_badge_label(:check), do: "Checked"
  defp action_badge_label(:call), do: "Called"
  defp action_badge_label(:bet), do: "Bet"
  defp action_badge_label(:raise), do: "Raised"

  attr :state, :map, required: true
  attr :my_seat, :integer, required: true

  defp action_bar(assigns) do
    hand = assigns.state.hand
    my = hand.seats[assigns.my_seat]
    to_call = min(hand.current_bet - my.contributed_this_street, my.stack)
    max_amount = my.stack + my.contributed_this_street
    min_bet = min(hand.big_blind, max_amount)
    min_raise_to = min(hand.current_bet + hand.min_raise, max_amount)
    min_amount = if hand.current_bet == 0, do: min_bet, else: min_raise_to

    assigns =
      assigns
      |> assign(:to_call, to_call)
      |> assign(:max_amount, max_amount)
      |> assign(:min_amount, min_amount)
      |> assign(:can_check?, my.contributed_this_street == hand.current_bet)
      |> assign(:can_raise_or_bet?, my.stack > to_call)
      |> assign(:bet_label, if(hand.current_bet == 0, do: "Bet", else: "Raise to"))
      |> assign(:quick_bets, quick_bets(pot_total(hand), min_amount, max_amount))

    ~H"""
    <div id="action-bar" class="flex flex-wrap items-center justify-center gap-2">
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
        Call {Tokens.format(@to_call)} Tokens
      </button>

      <button
        :for={{slug, label, amount} <- @quick_bets}
        :if={@can_raise_or_bet?}
        id={"quick-bet-#{slug}"}
        type="button"
        phx-click="bet_or_raise"
        phx-value-amount={amount}
        class="btn btn-sm btn-outline"
      >
        {label} &middot; {Tokens.format(amount)}
      </button>

      <form :if={@can_raise_or_bet?} phx-submit="bet_or_raise" class="flex items-center gap-2">
        <input
          type="range"
          name="amount"
          min={@min_amount}
          max={@max_amount}
          value={@min_amount}
          id="bet-amount-slider"
          phx-hook=".BetSlider"
          class="range range-sm w-32 sm:w-48"
        />
        <output id="bet-amount-output" class="w-16 text-right text-sm font-semibold">{Tokens.format(
          @min_amount
        )} Tokens</output>
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
            const amount = Number(this.el.value)
            this.output.textContent = amount.toLocaleString("en-US") + " Tokens"
          })
        }
      }
    </script>
    """
  end

  # Preset raise/bet-to amounts sized off the current pot, each shown only
  # when it's actually legal to submit - at least the big blind (the
  # opening-bet floor) and, once there's already a bet outstanding, at
  # least a full min-raise, both already folded into `min_amount`, and
  # never more than the player can cover (`max_amount`). A tiny pot early
  # in a hand can easily price a fraction below the big blind, which is
  # exactly when it's correctly left off rather than shown as a bet
  # nobody could actually make.
  defp quick_bets(pot, min_amount, max_amount) do
    [{"third", "1/3 Pot", pot / 3}, {"two-thirds", "2/3 Pot", pot * 2 / 3}, {"pot", "Pot", pot}]
    |> Enum.map(fn {slug, label, raw_amount} -> {slug, label, round(raw_amount)} end)
    |> Enum.filter(fn {_slug, _label, amount} ->
      amount >= min_amount and amount <= max_amount
    end)
  end

  attr :seat_index, :integer, required: true
  attr :table, :map, required: true
  attr :tokens_balance, :integer, required: true
  attr :amount, :integer, required: true
  attr :error, :string, default: nil

  defp join_modal(assigns) do
    min_buy_in = PokerTables.min_buy_in(assigns.table)
    max_buy_in = min(PokerTables.max_buy_in(assigns.table), assigns.tokens_balance)

    assigns = assigns |> assign(:min_buy_in, min_buy_in) |> assign(:max_buy_in, max_buy_in)

    ~H"""
    <div id="join-modal" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div
        phx-click-away="close_join"
        class="w-full max-w-sm rounded-2xl bg-base-100 p-6 shadow-xl"
      >
        <h2 class="text-lg font-bold">Buy in for seat {@seat_index + 1}</h2>
        <p class="mt-1 text-sm text-base-content/60">
          Between {Tokens.format(@min_buy_in)} and {Tokens.format(@max_buy_in)} Tokens.
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
            <div id="buy-in-amount" class="text-2xl font-bold">{Tokens.format(@amount)} Tokens</div>
            <div class="mt-2 flex gap-2">
              <button type="button" phx-click="close_join" class="btn btn-ghost btn-sm">Cancel</button>
              <button type="submit" id="confirm-join-button" class="btn btn-primary btn-sm">Sit down</button>
            </div>
          </form>
        <% else %>
          <p class="mt-4 text-sm text-error">
            You don't have enough Tokens for this table's minimum buy-in.
          </p>
          <button type="button" phx-click="close_join" class="btn btn-ghost btn-sm mt-4">Close</button>
        <% end %>
      </div>
    </div>
    """
  end

  defp hand_rankings_modal(assigns) do
    assigns = assign(assigns, :rankings, @hand_rankings)

    ~H"""
    <div
      id="hand-rankings-modal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    >
      <div
        phx-click-away="close_hand_rankings"
        class="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-2xl bg-base-100 p-6 shadow-xl"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="text-lg font-bold">Poker Hand Rankings</h2>
            <p class="mt-1 text-sm text-base-content/60">
              Best hand at the top, worst at the bottom.
            </p>
          </div>
          <button
            type="button"
            phx-click="close_hand_rankings"
            class="btn btn-ghost btn-sm btn-circle shrink-0"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <ol class="mt-4 flex flex-col gap-3">
          <li
            :for={{ranking, index} <- Enum.with_index(@rankings, 1)}
            class="flex flex-col items-center gap-2 rounded-xl bg-base-200 p-3"
          >
            <div class="flex items-center gap-2 self-start">
              <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-base-300 text-xs font-bold">
                {index}
              </span>
              <span class="font-semibold">{ranking.name}</span>
            </div>
            <div class="flex justify-center -space-x-8">
              <.card_face
                :for={{card, index} <- Enum.with_index(ranking.cards)}
                card={card}
                dim={index in ranking.kickers}
              />
            </div>
            <p class="text-center text-xs text-base-content/60">{ranking.description}</p>
          </li>
        </ol>
      </div>
    </div>
    """
  end

  @card_back_choices ~w(default black blue green red)
  @felt_color_choices ~w(green blue red)

  attr :user, :map, required: true

  defp settings_modal(assigns) do
    assigns =
      assigns
      |> assign(:card_backs, @card_back_choices)
      |> assign(:felt_colors, @felt_color_choices)

    ~H"""
    <div
      id="settings-modal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    >
      <div
        phx-click-away="close_settings"
        class="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-2xl bg-base-100 p-6 shadow-xl"
      >
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="text-lg font-bold">Table Settings</h2>
            <p class="mt-1 text-sm text-base-content/60">Only visible to you.</p>
          </div>
          <button
            type="button"
            phx-click="close_settings"
            class="btn btn-ghost btn-sm btn-circle shrink-0"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <div class="mt-5">
          <h3 class="text-sm font-semibold text-base-content/80">Card Back</h3>
          <div class="mt-2 grid grid-cols-5 gap-2">
            <button
              :for={choice <- @card_backs}
              type="button"
              id={"card-back-#{choice}"}
              phx-click="set_card_back"
              phx-value-choice={choice}
              class={[
                "rounded-lg border-2 p-1 transition",
                if(@user.card_back == choice,
                  do: "border-primary",
                  else: "border-transparent hover:border-base-300"
                )
              ]}
            >
              <img
                src={card_back_image(choice)}
                alt={choice}
                class="aspect-[7/10] w-full rounded object-contain"
              />
            </button>
          </div>
        </div>

        <div class="mt-5">
          <h3 class="text-sm font-semibold text-base-content/80">Table Felt</h3>
          <div class="mt-2 flex gap-3">
            <button
              :for={color <- @felt_colors}
              type="button"
              id={"felt-color-#{color}"}
              phx-click="set_felt_color"
              phx-value-choice={color}
              class={[
                "flex flex-col items-center gap-1 rounded-lg border-2 p-2 transition",
                if(@user.felt_color == color,
                  do: "border-primary",
                  else: "border-transparent hover:border-base-300"
                )
              ]}
            >
              <span class={["size-8 rounded-full bg-gradient-to-b", felt_gradient_class(color)]} />
              <span class="text-xs capitalize">{color}</span>
            </button>
          </div>
        </div>

        <div class="mt-5">
          <h3 class="text-sm font-semibold text-base-content/80">Mucking</h3>
          <p class="mt-1 text-xs text-base-content/60">
            Only applies to an uncontested win (everyone else folds) - a real showdown always lets you choose whether to show your cards.
          </p>
          <div class="mt-2 flex gap-2">
            <button
              type="button"
              id="muck-always-button"
              phx-click="set_muck_preference"
              phx-value-choice="always"
              class={[
                "btn btn-sm",
                if(@user.muck_preference == "always", do: "btn-primary", else: "btn-outline")
              ]}
            >
              Always muck cards
            </button>
            <button
              type="button"
              id="muck-never-button"
              phx-click="set_muck_preference"
              phx-value-choice="never"
              class={[
                "btn btn-sm",
                if(@user.muck_preference == "never", do: "btn-primary", else: "btn-outline")
              ]}
            >
              Never muck cards
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # The screen slot a seat renders in - relative to a seated viewer's own
  # seat, so a player sees themselves at `@seat_positions`' bottom-center
  # slot (index 0) with the rest of the table rotated around them the same
  # way it would be at a real table, rather than everyone sharing one
  # fixed, absolute layout. `view_anchor_seat` (the `my_seat_index` param
  # here) is `nil` for a spectator with no seat of their own, which falls
  # back to the natural, unrotated seat order - deliberately not the
  # current `button_seat`, which rotates every hand and would otherwise
  # make every player appear to change position each hand for anyone just
  # watching, with nothing seated to hold the frame steady against it.
  defp seat_position(seat_index, my_seat_index),
    do: Enum.at(@seat_positions, display_seat_index(seat_index, my_seat_index))

  defp display_seat_index(seat_index, nil), do: seat_index

  defp display_seat_index(seat_index, my_seat_index),
    do: rem(seat_index - my_seat_index + PokerTables.seats(), PokerTables.seats())

  # A seat's own `top`/`left` position, as literal Tailwind classes rather
  # than the inline `top: N%; left: N%;` style every other positioned
  # element on this page uses (see `.InlineStyle`) - deliberately, since an
  # inline style always wins over a class regardless of the class's own
  # media query, which would make it impossible for either `max-sm:`
  # override below to ever take effect. One clause per distinct value in
  # `@seat_positions` (5 `top`s, 7 `left`s), each a plain literal so
  # Tailwind's build-time scan can actually find and generate it.
  #
  # `top: 48` carries an override for the reason given in `@seat_positions`'
  # own doc comment (it sits in the community cards' band). The `left`
  # overrides are a separate, narrower problem: `w-36`(non-mine)/`w-64`
  # (mine) seat cards, centered via `-translate-x-1/2` on an anchor as far
  # out as 6%/94%, overhang past the felt - and on a narrow phone, past the
  # viewport itself with no scrollbar to reach it - regardless of how much
  # margin the felt itself has (widening the felt just moves the same
  # relative overhang further in absolute pixels, it doesn't remove it).
  # Pulling the anchor in on mobile, together with the non-mine seat/
  # hole-card width already shrinking a step earlier at this breakpoint,
  # keeps the card and username readable within the screen instead of
  # clipped off either edge.
  defp seat_top_class(0), do: "top-[0%]"
  defp seat_top_class(12), do: "top-[12%]"
  defp seat_top_class(48), do: "top-[48%] max-sm:top-[24%]"
  defp seat_top_class(80), do: "top-[80%]"
  defp seat_top_class(94), do: "top-[94%]"

  defp seat_left_class(6), do: "left-[6%] max-sm:left-[18%]"
  defp seat_left_class(10), do: "left-[10%] max-sm:left-[22%]"
  defp seat_left_class(12), do: "left-[12%] max-sm:left-[22%]"
  defp seat_left_class(50), do: "left-[50%]"
  defp seat_left_class(88), do: "left-[88%] max-sm:left-[76%]"
  defp seat_left_class(90), do: "left-[90%] max-sm:left-[78%]"
  defp seat_left_class(94), do: "left-[94%] max-sm:left-[82%]"

  # Well over halfway from the seat toward the felt's center - clear of
  # the (fairly tall, once a hand's dealt) seat marker's own name/stack
  # text and hole cards, short of actually sitting in the pot. Under half
  # sat close enough to the seat that its own content could reach up and
  # overlap it, worst on the bottom ("mine") seat, whose hole cards are
  # the biggest on the table.
  defp bet_chip_position(seat_index, my_seat_index) do
    seat = seat_position(seat_index, my_seat_index)
    %{top: along(seat.top, @center.top), left: along(seat.left, @center.left)}
  end

  defp along(from, to), do: from + (to - from) * 0.65

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

  defp reveal_hole_cards?(nil, _mine?, _hand, _seat_index), do: false
  defp reveal_hole_cards?(_hand_seat, true, _hand, _seat_index), do: true

  # An uncontested winner's cards only show once they've chosen to reveal
  # them (see `Poker.reveal_hand/2`) - a genuine showdown's winner(s) are
  # already force-revealed by `Poker.showdown/1` itself by the time this
  # runs. Everyone else who didn't fold (i.e. a showdown participant who
  # lost) is still shown automatically either way.
  defp reveal_hole_cards?(hand_seat, false, hand, seat_index) do
    hand.status == :hand_over and hand_seat.status != :folded and
      (seat_index not in Poker.winning_seats(hand) or seat_index in hand.revealed_seats)
  end

  # Whether `seat_index` still has an open "show my cards" offer - it won
  # this now-finished hand but hasn't revealed yet. Only ever true for the
  # viewer's own seat (gated by `mine?` at the call site).
  #
  # An uncontested win (not a real showdown - see `Poker.showdown?/1`) with
  # "always muck" set hides the offer outright, since the player never
  # wants to be asked. "Never muck" needs no clause here at all: the
  # winning seat is already in `revealed_seats` by the time this runs (see
  # `PokerTable`'s `auto_reveal_never_muck/1`), so the plain
  # `not in hand.revealed_seats` check below already excludes it. A real
  # showdown's winner is likewise already in `revealed_seats` by the time
  # this runs (forced by `Poker.showdown/1` itself, not a preference), so
  # the same check excludes them too - there's no muck option to offer.
  # This function only ever ends up offering the button for an uncontested
  # win the player hasn't set "always muck" for.
  defp can_reveal?(%Poker{status: :hand_over} = hand, seat_index, muck_preference) do
    seat_index in Poker.winning_seats(hand) and seat_index not in hand.revealed_seats and
      not (muck_preference == "always" and not Poker.showdown?(hand))
  end

  defp can_reveal?(_hand, _seat_index, _muck_preference), do: false

  # Blue is checked against the app's own dark navy-tinted background
  # (`--color-base-100`/`-200`, both low-chroma blues in the same hue
  # family) so it doesn't wash out against the page behind the felt -
  # Tailwind's blue-900/950 are saturated enough to still read as a
  # distinct, deliberate felt rather than blending into the page.
  defp felt_gradient_class("blue"), do: "from-blue-900 to-blue-950"
  defp felt_gradient_class("red"), do: "from-red-900 to-red-950"
  defp felt_gradient_class(_green_or_other), do: "from-emerald-900 to-emerald-950"

  # The viewer's own live "what do I have" read - only once there's
  # something to rank (the flop is down: 2 hole + at least 3 community
  # cards) and only while the hand's still being played, since a finished
  # hand's category is already called out in the showdown/winner banner.
  defp my_hand_category(hand_seat, %Poker{status: :in_progress, community_cards: community})
       when length(community) >= 3 do
    (hand_seat.hole_cards ++ community) |> HandEvaluator.rank() |> HandEvaluator.category_name()
  end

  defp my_hand_category(_hand_seat, _hand), do: nil

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

  # A stable key that changes exactly once, right when a hand ends with a
  # single winner - deliberately not tied to `pot_total` (the natural
  # choice, matching `.ChipFlight`'s existing growth-triggered
  # `data-flight-key`), because `pot_total` *doesn't* actually change at
  # the in-progress -> hand_over transition: `Poker.showdown/1`'s pot
  # amounts are just a re-bucketing of the same `total_contributed`
  # figures already summed while live, so reusing that key would never
  # fire a fresh animation for the payout itself. `nil` (hand still live,
  # or no single winner) tells the hook there's no payout flight to play.
  defp payout_flight_key(%Poker{status: :hand_over} = hand) do
    case Poker.winning_seats(hand) do
      [seat] -> "#{pot_total(hand)}-#{seat}"
      _ -> nil
    end
  end

  defp payout_flight_key(_hand), do: nil

  # The pot's flight offset (percent of the felt, matching `.ChipFlight`'s
  # existing entry-flight `dx`/`dy` convention) from its resting spot
  # (`@pot_position`) to the winning seat's own anchor - all the way
  # there, not the partway `bet_chip_position/2` waypoint a live bet
  # rests at, so the payout reads as chips actually arriving at the
  # player rather than drifting toward the middle of the table. A split
  # pot (more than one distinct winning seat, whether from one pot split
  # multiple ways or separate side pots going to different seats) has no
  # single destination, so the offset is zero and it doesn't move - the
  # winner banner's text explains it instead.
  defp payout_offset(hand, my_seat_index) do
    case Poker.winning_seats(hand) do
      [seat] ->
        destination = seat_position(seat, my_seat_index)
        %{dx: destination.left - @pot_position.left, dy: destination.top - @pot_position.top}

      _ ->
        %{dx: 0, dy: 0}
    end
  end

  # The showdown/uncontested-win callout: one clause per pot (almost
  # always just one), each naming its winner(s), the amount they took,
  # and - only when a real showdown happened for that pot (more than one
  # seat was still eligible for it, and all five community cards are out)
  # rather than everyone else simply folding - the winning hand's
  # category, e.g. "Flush".
  defp winner_text(%Poker{status: :hand_over} = hand),
    do:
      hand.pots
      |> merge_pots_by_winners()
      |> Enum.map(&pot_summary(&1, hand))
      |> Enum.join("  •  ")

  defp winner_text(_hand), do: nil

  # `Poker.showdown/1` builds one pot per distinct contribution tier - the
  # standard side-pot algorithm, correct for capping what a short-stacked
  # all-in seat can win. But a tier boundary just as often comes from a
  # seat *folding* after posting a blind rather than going all-in, and
  # since a folded seat is never eligible for any pot regardless of tier,
  # that split changes nothing about who's eligible - every pot on either
  # side of it ends up with the exact same winner(s). Left unmerged, that
  # announces as "X wins 600 Tokens ... X wins 400 Tokens ..." back to
  # back, reading as a duplicated/glitched message rather than the two
  # separate (if only technically separate) pots it actually is. Adjacent
  # pots only - `showdown/1` emits them in ascending contribution order,
  # and eligibility only ever shrinks (never reopens) as the level rises,
  # so two pots sharing a winner set can't have a different-winner pot
  # sandwiched between them. This only simplifies the announcement - the
  # actual per-seat chip awards already happened in `Poker.showdown/1`
  # against the unmerged pots, and are untouched here.
  defp merge_pots_by_winners(pots) do
    pots
    |> Enum.reduce([], fn pot, acc ->
      case acc do
        [%{winners: winners} = last | rest] when winners == pot.winners ->
          merged = %{
            last
            | amount: last.amount + pot.amount,
              eligible: Enum.uniq(last.eligible ++ pot.eligible)
          }

          [merged | rest]

        _ ->
          [pot | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp pot_summary(pot, hand) do
    names = pot.winners |> Enum.map(&Map.fetch!(hand.seats, &1).username) |> Enum.join(" & ")
    plural = if length(pot.winners) == 1, do: "s", else: ""
    suffix = if name = showdown_hand_name(pot, hand), do: " with a #{name}", else: ""
    "#{names} win#{plural} #{Tokens.format(pot.amount)} Tokens#{suffix}"
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
end
