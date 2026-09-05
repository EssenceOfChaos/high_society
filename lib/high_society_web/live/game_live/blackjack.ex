defmodule HighSocietyWeb.GameLive.Blackjack do
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games
  alias HighSociety.Games.Blackjack
  alias HighSociety.Money

  @impl true
  def mount(_params, _session, socket) do
    blackjack_game = Games.get_active_blackjack_game(socket.assigns.current_scope)

    socket =
      assign(socket,
        blackjack_game: blackjack_game,
        pending_bets: %{0 => 0, 1 => 0},
        second_hand?: false,
        round_dismissed?: false,
        bet_error: nil
      )

    socket =
      cond do
        not connected?(socket) ->
          socket

        betting?(socket.assigns) ->
          push_event(socket, "play_sounds", %{sounds: ["place-your-bets"]})

        # A LiveView process can restart (a deploy, a crash, a code reload
        # while iterating in dev) while a round is mid-`dealer_turn`, which
        # is normally paced along by a self-scheduled `:dealer_step`
        # message. That timer dies with the old process, so without this
        # the round would be stuck forever with no further sound, card, or
        # button to move it along - resuming it here re-arms that pacing
        # for whatever round was left mid-flight.
        blackjack_game.status == "dealer_turn" ->
          Process.send_after(self(), :dealer_step, dealer_step_delay())
          socket

        true ->
          socket
      end

    {:ok, socket}
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

    socket =
      socket
      |> assign(pending_bets: pending_bets)
      |> push_event("play_sounds", %{sounds: ["placing-chips"]})

    {:noreply, socket}
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
          |> update_blackjack_game(blackjack_game, user, deal_sounds(blackjack_game))

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, bet_error: bet_error_message(reason))}
    end
  end

  def handle_event("hit", _params, socket) do
    hand_id = socket.assigns.blackjack_game.active_hand

    {blackjack_game, user} =
      Games.hit(socket.assigns.current_scope, socket.assigns.blackjack_game)

    hand = Enum.find(blackjack_game.hands, &(&1["id"] == hand_id))
    sounds = hit_result_sounds(hand) ++ turn_advance_sounds(blackjack_game, hand_id)

    {:noreply, update_blackjack_game(socket, blackjack_game, user, sounds)}
  end

  def handle_event("stand", _params, socket) do
    hand_id = socket.assigns.blackjack_game.active_hand

    {blackjack_game, user} =
      Games.stand(socket.assigns.current_scope, socket.assigns.blackjack_game)

    sounds = ["player-stand"] ++ turn_advance_sounds(blackjack_game, hand_id)

    {:noreply, update_blackjack_game(socket, blackjack_game, user, sounds)}
  end

  def handle_event("double_down", _params, socket) do
    hand_id = socket.assigns.blackjack_game.active_hand

    case Games.double_down(socket.assigns.current_scope, socket.assigns.blackjack_game) do
      {:ok, blackjack_game, user} ->
        hand = Enum.find(blackjack_game.hands, &(&1["id"] == hand_id))

        sounds =
          ["double-down"] ++
            hit_result_sounds(hand) ++ turn_advance_sounds(blackjack_game, hand_id)

        {:noreply, update_blackjack_game(socket, blackjack_game, user, sounds)}

      {:error, :insufficient_funds} ->
        {:noreply, put_flash(socket, :error, "You don't have enough chips to double down.")}

      {:error, :invalid_action} ->
        {:noreply, socket}
    end
  end

  def handle_event("split", _params, socket) do
    case Games.split(socket.assigns.current_scope, socket.assigns.blackjack_game) do
      {:ok, blackjack_game, user} ->
        sounds =
          case Enum.find(blackjack_game.hands, &(&1["id"] == blackjack_game.active_hand)) do
            nil -> ["player-split"]
            hand -> ["player-split"] ++ hand_value_sounds(hand["cards"])
          end

        {:noreply, update_blackjack_game(socket, blackjack_game, user, sounds)}

      {:error, :insufficient_funds} ->
        {:noreply, put_flash(socket, :error, "You don't have enough chips to split.")}

      {:error, :invalid_action} ->
        {:noreply, socket}
    end
  end

  def handle_event("change_bet", _params, socket) do
    socket =
      socket
      |> assign(round_dismissed?: true)
      |> push_event("play_sounds", %{sounds: ["place-your-bets"]})

    {:noreply, socket}
  end

  def handle_event("rebet", _params, socket) do
    bets = rebet_amounts(socket.assigns.blackjack_game)

    case Games.start_blackjack_round(socket.assigns.current_scope, bets) do
      {:ok, blackjack_game} ->
        user = Accounts.get_user!(socket.assigns.current_scope.user.id)

        socket =
          socket
          |> assign(pending_bets: %{0 => 0, 1 => 0}, round_dismissed?: false, bet_error: nil)
          |> update_blackjack_game(blackjack_game, user, deal_sounds(blackjack_game))

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(
            pending_bets: Map.merge(%{0 => 0, 1 => 0}, bets),
            second_hand?: map_size(bets) > 1,
            round_dismissed?: true,
            bet_error: bet_error_message(reason)
          )
          |> push_event("play_sounds", %{sounds: ["place-your-bets"]})

        {:noreply, socket}
    end
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
  # socket, queuing `extra_sounds` (the sound(s) for whatever action just
  # happened) via the narration queue, alongside whatever the game's new
  # status calls for on its own: when the game has just entered (or is still
  # in) the dealer's turn, that's the matching reveal/hit sound - fired on
  # its own independent channel (`play_sound`, not the `play_sounds` queue)
  # so it plays right away in sync with the hole card flipping over in this
  # same render, rather than waiting behind any narration for the action
  # that ended the player's turn - plus scheduling the next paced step so
  # the dealer's hole-card reveal and subsequent hits/busts play out one
  # card at a time instead of resolving instantly; when the round has just
  # settled, it's each hand's outcome sound.
  defp update_blackjack_game(socket, blackjack_game, user, extra_sounds \\ [])

  defp update_blackjack_game(
         socket,
         %{status: "dealer_turn"} = blackjack_game,
         user,
         extra_sounds
       ) do
    sound = if length(blackjack_game.dealer_hand) == 2, do: "flip", else: "deal"
    Process.send_after(self(), :dealer_step, dealer_step_delay())

    socket =
      socket
      |> assign(blackjack_game: blackjack_game, current_scope: Scope.for_user(user))
      |> push_event("play_sound", %{sound: sound})

    if extra_sounds == [],
      do: socket,
      else: push_event(socket, "play_sounds", %{sounds: extra_sounds})
  end

  defp update_blackjack_game(socket, %{status: "round_over"} = blackjack_game, user, extra_sounds) do
    sounds = extra_sounds ++ round_over_sounds(blackjack_game)

    socket = assign(socket, blackjack_game: blackjack_game, current_scope: Scope.for_user(user))
    if sounds == [], do: socket, else: push_event(socket, "play_sounds", %{sounds: sounds})
  end

  defp update_blackjack_game(socket, blackjack_game, user, extra_sounds) do
    socket = assign(socket, blackjack_game: blackjack_game, current_scope: Scope.for_user(user))

    if extra_sounds == [],
      do: socket,
      else: push_event(socket, "play_sounds", %{sounds: extra_sounds})
  end

  defp dealer_step_delay,
    do: Application.get_env(:high_society, :blackjack_dealer_step_delay_ms, 900)

  # The sound(s) for a hand right after it took a card (hit or double down):
  # a bust gets its own reaction; otherwise the hand's new value is read out.
  defp hit_result_sounds(%{"status" => "busted"}), do: ["player-bust"]
  defp hit_result_sounds(hand), do: hand_value_sounds(hand["cards"])

  # Announces the hand the turn just moved on to - e.g. box 0 finishes and
  # box 1 becomes active - but only when it's genuinely a different hand
  # than the one the action was just taken on (a still-player_turn status
  # after acting on the same hand id would mean nothing advanced, which
  # doesn't happen here but is guarded against for safety).
  defp turn_advance_sounds(
         %{status: "player_turn", active_hand: active_hand} = game,
         prior_hand_id
       )
       when active_hand != prior_hand_id do
    case Enum.find(game.hands, &(&1["id"] == active_hand)) do
      nil -> []
      hand -> hand_value_sounds(hand["cards"])
    end
  end

  defp turn_advance_sounds(_game, _prior_hand_id), do: []

  # Announces the hand the player is about to act on first - not every
  # dealt hand at once, since the second box hasn't come up yet and will
  # get its own announcement via `turn_advance_sounds/2` once play reaches
  # it. A natural blackjack (dealer or player) never becomes the active
  # hand, so both cases fall through to no announcement on their own: the
  # round-over outcome sound covers a player natural, and a dealer natural
  # skips narration entirely by virtue of there being no active hand to
  # find.
  defp deal_sounds(%{hands: hands, active_hand: active_hand}) do
    case Enum.find(hands, &(&1["id"] == active_hand)) do
      nil -> []
      hand -> hand_value_sounds(hand["cards"])
    end
  end

  # A dealer natural blackjack ends the round for every hand at once, so it
  # gets a single "dealer has blackjack" instead of one per hand.
  # Otherwise, each hand gets its own outcome sound.
  defp round_over_sounds(%{hands: hands, dealer_hand: dealer_hand}) do
    if Blackjack.blackjack?(dealer_hand) do
      ["dealer-blackjack"]
    else
      hands |> Enum.map(&outcome_sound/1) |> Enum.reject(&is_nil/1)
    end
  end

  # A bust was already announced live in `hit_result_sounds/1`, so it stays
  # silent here. A push has no dedicated clip of its own (the dealer
  # natural blackjack push is handled up in `round_over_sounds/1` instead).
  defp outcome_sound(%{"status" => "busted"}), do: nil
  defp outcome_sound(%{"outcome" => "push"}), do: nil
  defp outcome_sound(%{"outcome" => "blackjack_win"}), do: "player-blackjack"
  defp outcome_sound(%{"outcome" => "win"}), do: "player-wins"
  defp outcome_sound(%{"outcome" => "loss"}), do: "dealer-wins"

  # The audio clips for a hand's total: e.g. "6H"+"5D" -> ["eleven"], but a
  # hand with an ace still counted as 11 (a "soft" hand) is genuinely
  # ambiguous - e.g. "AS"+"5H" is both 6 and 16 - so it reads out both
  # separated by "or", same as a dealer would call it at the table.
  defp hand_value_sounds(cards) do
    high = Blackjack.value(cards)
    low = hard_total(cards)

    if high == low + 10,
      do: [number_word(low), "or", number_word(high)],
      else: [number_word(high)]
  end

  defp hard_total(cards) do
    Enum.reduce(cards, 0, fn card, total ->
      {rank, _suit} = Blackjack.split_card(card)
      total + hard_rank_value(rank)
    end)
  end

  defp hard_rank_value("A"), do: 1
  defp hard_rank_value(rank) when rank in ~w(J Q K), do: 10
  defp hard_rank_value(rank), do: String.to_integer(rank)

  defp number_word(2), do: "two"
  defp number_word(3), do: "three"
  defp number_word(4), do: "four"
  defp number_word(5), do: "five"
  defp number_word(6), do: "six"
  defp number_word(7), do: "seven"
  defp number_word(8), do: "eight"
  defp number_word(9), do: "nine"
  defp number_word(10), do: "ten"
  defp number_word(11), do: "eleven"
  defp number_word(12), do: "twelve"
  defp number_word(13), do: "thirteen"
  defp number_word(14), do: "fourteen"
  defp number_word(15), do: "fifteen"
  defp number_word(16), do: "sixteen"
  defp number_word(17), do: "seventeen"
  defp number_word(18), do: "eighteen"
  defp number_word(19), do: "nineteen"
  defp number_word(20), do: "twenty"
  defp number_word(21), do: "twenty-one"

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
                ${Money.format(@current_scope.user.balance)}
              </div>
            </div>
            <button
              :if={is_nil(@current_scope.user.claimed_starting_chips_at)}
              id="claim-chips-button"
              type="button"
              phx-click="claim_starting_chips"
              class="btn btn-success btn-sm animate-pulse"
            >
              Claim ${Money.format(Accounts.starting_chip_amount())}
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
            Max ${Money.format(Blackjack.max_bet())} per hand.
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
              class={[
                "btn btn-primary btn-lg px-12",
                total_bet(@pending_bets) > 0 && "animate-pulse"
              ]}
            >
              Deal
            </button>
          </div>
        </div>

        <div :if={!betting?(assigns)} id="blackjack-table" class="mt-8">
          <div class="relative flex flex-col items-center gap-2 rounded-t-2xl bg-cover bg-top bg-[url(/images/blackjack-felt.png)] px-4 pb-6 pt-6 shadow-xl">
            <span class="flex items-center gap-1.5 rounded-full bg-black/55 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-amber-100 shadow">
              Dealer<span :if={@blackjack_game.status != "player_turn"}>
                — {Blackjack.value(@blackjack_game.dealer_hand)}
              </span>
              <.icon
                :if={@blackjack_game.status == "dealer_turn"}
                name="hero-arrow-path"
                class="size-3 motion-safe:animate-spin"
              />
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

            <div :if={@blackjack_game.status == "round_over"} class="mt-8 flex justify-center gap-3">
              <button
                id="rebet-button"
                type="button"
                phx-click="rebet"
                class="btn btn-lg animate-pulse gap-2 border-none bg-amber-500 px-12 text-amber-950 hover:bg-amber-400"
              >
                <span class="blackjack-action-icon blackjack-action-icon-rebet size-5"></span> Rebet
              </button>
              <button
                id="change-bet-button"
                type="button"
                phx-click="change_bet"
                class="btn btn-lg border border-amber-100/50 bg-transparent px-12 text-amber-100 hover:bg-amber-100/10 hover:text-amber-50"
              >
                Change bet
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
            this.specialSrc = {
              deal: "/audio/card-deal.mp3",
              flip: "/audio/card-flip.mp3"
            }
            this.queue = []
            this.playing = false

            // Fires a sound immediately on its own channel, independent of
            // the narration queue below - used for the dealer's card
            // reveal/hit SFX so it stays in sync with the card flipping
            // over in the same render, instead of waiting behind whatever
            // narration the player's own action queued up first.
            this.handleEvent("play_sound", ({sound}) => {
              if (localStorage.getItem("high_society:sound_muted") === "true") return

              const src = this.specialSrc[sound] || `/audio/${sound}.aac`
              new Audio(src).play().catch(() => {})
            })

            this.handleEvent("play_sounds", ({sounds}) => {
              if (localStorage.getItem("high_society:sound_muted") === "true") return

              this.queue.push(...sounds)
              this.playNext()
            })
          },
          playNext() {
            if (this.playing) return

            const name = this.queue.shift()
            if (!name) return

            const src = this.specialSrc[name] || `/audio/${name}.aac`
            const audio = new Audio(src)
            this.playing = true

            const advance = () => {
              this.playing = false
              this.playNext()
            }

            audio.addEventListener("ended", advance)
            audio.addEventListener("error", advance)
            audio.play().catch(advance)
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
        id="remove-second-hand-button"
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
      <div id={"bet-amount-#{@box}"} class="text-2xl font-bold">${Money.format(@amount)}</div>
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
          ${Money.format(chip)}
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

  defp chip_color(500), do: "border-neutral-400 bg-neutral-100 text-neutral-900"
  defp chip_color(2_500), do: "border-red-300 bg-red-600 text-white"
  defp chip_color(10_000), do: "border-neutral-600 bg-neutral-900 text-white"
  defp chip_color(50_000), do: "border-amber-300 bg-amber-500 text-amber-950"

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
      <span class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-amber-100/60">
        <span
          :if={@active? && @status == "player_turn"}
          class="relative flex size-2"
          title="Your turn"
        >
          <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-amber-400 opacity-75"></span>
          <span class="relative inline-flex size-2 rounded-full bg-amber-500"></span>
        </span>
        {@label} — Bet ${Money.format(@hand["bet"])}{if @hand["doubled"], do: " (doubled)"} — {Blackjack.value(
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
          @hand["outcome"] in ["win", "blackjack_win"] &&
            "animate-bounce text-emerald-400 [animation-iteration-count:2]",
          @hand["outcome"] == "push" && "text-amber-100/70",
          @hand["outcome"] == "loss" && "text-red-400"
        ]}
      >
        {outcome_message(@hand)}
      </p>
      <div :if={@active? && @status == "player_turn"} class="mt-3 flex flex-wrap justify-center gap-3">
        <button
          id={"hit-button-#{@hand["id"]}"}
          type="button"
          phx-click="hit"
          class="btn btn-md gap-2 border-none bg-emerald-600 text-white hover:bg-emerald-500"
        >
          <span class="blackjack-action-icon blackjack-action-icon-hit size-5"></span> Hit
        </button>
        <button
          id={"stand-button-#{@hand["id"]}"}
          type="button"
          phx-click="stand"
          class="btn btn-md gap-2 border-none bg-red-700 text-white hover:bg-red-600"
        >
          <span class="blackjack-action-icon blackjack-action-icon-stand size-5"></span> Stand
        </button>
        <button
          :if={@can_double_down?}
          id={"double-button-#{@hand["id"]}"}
          type="button"
          phx-click="double_down"
          class="btn btn-md gap-2 border-none bg-indigo-600 text-white hover:bg-indigo-500"
        >
          <span class="blackjack-action-icon blackjack-action-icon-double size-5"></span> Double
        </button>
        <button
          :if={@can_split?}
          id={"split-button-#{@hand["id"]}"}
          type="button"
          phx-click="split"
          class="btn btn-md gap-2 border-none bg-amber-600 text-white hover:bg-amber-500"
        >
          <span class="blackjack-action-icon blackjack-action-icon-split size-5"></span> Split
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
        letter =
          Enum.find_index(siblings, &(&1["id"] == hand["id"])) |> then(&Enum.at(["A", "B"], &1))

        "Hand #{hand["box"] + 1}#{letter}"
    end
  end

  defp betting?(assigns), do: is_nil(assigns.blackjack_game) or assigns.round_dismissed?

  # Recovers each box's original wager from the just-finished round, so
  # "Rebet" can re-deal without the player re-selecting chips. Splits don't
  # change the per-box stake (both resulting hands share the original bet),
  # but doubling does, so a doubled hand's bet is halved back to what was
  # originally placed on that box.
  defp rebet_amounts(%{hands: hands}) do
    hands
    |> Enum.uniq_by(& &1["box"])
    |> Map.new(fn hand -> {hand["box"], original_bet(hand)} end)
  end

  defp original_bet(%{"doubled" => true, "bet" => bet}), do: div(bet, 2)
  defp original_bet(%{"bet" => bet}), do: bet

  defp chip_values, do: [500, 2_500, 10_000, 50_000]

  defp total_bet(pending_bets), do: pending_bets |> Map.values() |> Enum.sum()

  defp bet_error_message(:no_bets), do: "Place a bet on at least one box before dealing."

  defp bet_error_message(:bet_too_large),
    do: "Max bet is $#{Money.format(Blackjack.max_bet())} per box."

  defp bet_error_message(:insufficient_funds), do: "You don't have enough chips for that bet."

  defp outcome_message(%{"outcome" => "blackjack_win", "payout" => payout}),
    do: "Blackjack! +$#{Money.format(payout)}"

  defp outcome_message(%{"outcome" => "win", "payout" => payout}),
    do: "Win +$#{Money.format(payout)}"

  defp outcome_message(%{"outcome" => "push", "payout" => payout}),
    do: "Push — $#{Money.format(payout)} returned"

  defp outcome_message(%{"outcome" => "loss"}), do: "Loss"
  defp outcome_message(_hand), do: nil
end
