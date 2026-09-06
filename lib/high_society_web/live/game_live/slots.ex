defmodule HighSocietyWeb.GameLive.Slots do
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games
  alias HighSociety.Games.Slots
  alias HighSociety.Money

  import HighSocietyWeb.GameLive.SlotsComponents

  @impl true
  def mount(_params, _session, socket) do
    slots_game = Games.get_active_slots_game(socket.assigns.current_scope)

    socket =
      assign(socket,
        slots_game: slots_game,
        pending_slots_game: nil,
        spinning?: false,
        wager: (slots_game && slots_game.wager) || List.first(Slots.wager_options()),
        wager_options: Slots.wager_options(),
        error: nil,
        bonus_round_won: 0,
        bonus_round_summary: nil
      )

    if connected?(socket), do: maybe_schedule_free_spin(socket)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_wager", %{"amount" => amount}, socket) do
    if free_spins_active?(socket.assigns.slots_game) do
      {:noreply, socket}
    else
      {:noreply, assign(socket, wager: String.to_integer(amount), error: nil)}
    end
  end

  def handle_event("spin", _params, %{assigns: %{spinning?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("spin", _params, socket) do
    # Free spins advance on their own timer (see :auto_spin below) - a
    # manual click during an active round is ignored rather than firing a
    # second, redundant spin.
    if free_spins_active?(socket.assigns.slots_game) do
      {:noreply, socket}
    else
      start_spin(socket, socket.assigns.wager)
    end
  end

  def handle_event("claim_slots_chips", _params, socket) do
    case Accounts.claim_slots_chips(socket.assigns.current_scope.user) do
      {:ok, user} -> {:noreply, assign(socket, current_scope: Scope.for_user(user))}
      {:error, :already_claimed} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:reveal_spin, socket) do
    slots_game = socket.assigns.pending_slots_game

    # Whether the spin that just resolved was itself a free spin (as
    # opposed to the regular paid spin that triggered the round) - tells
    # us whether to keep adding to the running bonus-round total or start
    # a fresh one.
    was_free_spin? = free_spins_active?(socket.assigns.slots_game)

    bonus_round_won =
      if was_free_spin?, do: socket.assigns.bonus_round_won + slots_game.total_win, else: 0

    # Once the last free spin resolves, surface the round's running total
    # as its own summary - distinct from the per-spin "you won" line,
    # which keeps announcing just that spin's own result as always.
    bonus_round_summary =
      if was_free_spin? and slots_game.free_spins_remaining == 0, do: bonus_round_won

    # A spin that triggers/retriggers the bonus only announces the bonus
    # fanfare - stacking the win/lose narration right after it read as
    # strange, since the bonus is the headline result of that spin.
    sounds =
      if slots_game.bonus_triggered, do: ["bonus-trigger"], else: [result_sound(slots_game)]

    socket =
      socket
      |> assign(
        slots_game: slots_game,
        pending_slots_game: nil,
        spinning?: false,
        bonus_round_won: bonus_round_won,
        bonus_round_summary: bonus_round_summary
      )
      |> push_event("play_sounds", %{sounds: sounds})

    maybe_schedule_free_spin(socket)

    {:noreply, socket}
  end

  def handle_info(:auto_spin, %{assigns: %{spinning?: true}} = socket), do: {:noreply, socket}

  def handle_info(:auto_spin, socket) do
    if free_spins_active?(socket.assigns.slots_game) do
      start_spin(socket, socket.assigns.wager)
    else
      {:noreply, socket}
    end
  end

  defp start_spin(socket, wager) do
    case Games.spin(socket.assigns.current_scope, wager) do
      {:ok, slots_game, user} ->
        socket =
          socket
          |> assign(
            pending_slots_game: slots_game,
            spinning?: true,
            current_scope: Scope.for_user(user),
            error: nil,
            bonus_round_summary: nil
          )
          |> push_event("play_sound", %{sound: "lever-pull"})
          |> push_event("play_sound", %{sound: "reel-spin"})

        Process.send_after(self(), :reveal_spin, spin_reveal_delay())

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, error: spin_error_message(reason))}
    end
  end

  # Free spins are won, not spent - once the bonus round starts, it plays
  # itself out on a timer rather than waiting on a click for every spin,
  # continuing automatically until the round's spin count runs out.
  defp maybe_schedule_free_spin(socket) do
    if free_spins_active?(socket.assigns.slots_game) do
      Process.send_after(self(), :auto_spin, free_spin_delay())
    end
  end

  defp free_spins_active?(nil), do: false
  defp free_spins_active?(%{free_spins_remaining: n}), do: n > 0

  defp spin_error_message(:invalid_wager), do: "Pick a valid wager amount."
  defp spin_error_message(:insufficient_funds), do: "You don't have enough chips for that wager."

  defp result_sound(%{total_win: 0}), do: "spin-lose"

  defp result_sound(%{total_win: win, wager: wager}) do
    cond do
      win / wager >= 40 -> "win-jackpot"
      win / wager >= 10 -> "win-big"
      win / wager >= 2 -> "win-medium"
      true -> "win-small"
    end
  end

  defp spin_reveal_delay,
    do: Application.get_env(:high_society, :slots_spin_reveal_delay_ms, 1800)

  defp free_spin_delay,
    do: Application.get_env(:high_society, :slots_free_spin_delay_ms, 1400)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="slots-screen"
        class="mx-auto max-w-4xl"
        phx-hook=".SoundEffects"
        data-spinning={to_string(@spinning?)}
      >
        <div class="flex items-center justify-between">
          <div>
            <.link navigate={~p"/#games"} class="text-sm text-base-content/60 hover:text-base-content">
              &larr; All games
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">Slots</h1>
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
              :if={is_nil(@current_scope.user.claimed_slots_chips_at)}
              id="claim-chips-button"
              type="button"
              phx-click="claim_slots_chips"
              class="btn btn-success btn-sm animate-pulse"
            >
              Claim ${Money.format(Accounts.slots_starting_chip_amount())}
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

        <p :if={@error} class="mt-4 alert alert-error text-sm">{@error}</p>

        <div class="mt-6 flex justify-center">
          <.cabinet bonus?={free_spins_active?(@slots_game)}>
            <.grid
              grid={@slots_game && @slots_game.grid}
              wins={(@slots_game && @slots_game.wins) || []}
              spinning?={@spinning?}
              bonus_triggered?={!!(@slots_game && !@spinning? && @slots_game.bonus_triggered)}
            />
          </.cabinet>
        </div>

        <div :if={@slots_game && !@spinning?} class="mt-4 min-h-8 text-center">
          <p
            :if={@slots_game.bonus_triggered}
            class="animate-pulse text-lg font-bold text-emerald-400"
          >
            🎉 Bonus! {free_spins_label(@slots_game)}
          </p>
          <p :if={@slots_game.total_win > 0} class="text-xl font-bold text-success">
            You won ${Money.format(@slots_game.total_win)}!
          </p>
          <p
            :if={@slots_game.total_win == 0 && !@slots_game.bonus_triggered}
            class="text-base-content/60"
          >
            Try again.
          </p>
          <p :if={@bonus_round_summary} class="mt-1 text-base font-semibold text-emerald-300">
            🏆 Bonus round total: ${Money.format(@bonus_round_summary)}
          </p>
        </div>

        <div class="mt-8 flex flex-col items-center gap-3">
          <div
            :if={free_spins_active?(@slots_game)}
            class="rounded-full bg-emerald-500/20 px-4 py-2 text-sm font-semibold text-emerald-300"
          >
            Free Spins remaining: {@slots_game.free_spins_remaining} &middot; {@slots_game.free_spin_multiplier}x multiplier
          </div>

          <form :if={!free_spins_active?(@slots_game)} id="wager-form" phx-change="select_wager">
            <select id="wager-select" name="amount" class="select select-bordered select-sm">
              <option :for={amount <- @wager_options} value={amount} selected={@wager == amount}>
                ${Money.format(amount)}
              </option>
            </select>
          </form>

          <p
            :if={free_spins_active?(@slots_game)}
            id="auto-spin-indicator"
            class="text-sm font-medium text-emerald-300"
          >
            <.icon name="hero-arrow-path" class="mr-1 inline size-4 animate-spin" />
            Bonus round in progress — spinning automatically&hellip;
          </p>

          <button
            :if={!free_spins_active?(@slots_game)}
            id="spin-button"
            type="button"
            phx-click="spin"
            disabled={@spinning?}
            class="btn btn-primary btn-lg px-16"
          >
            Spin — ${Money.format(@wager)}
          </button>
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
            this.queue = []
            this.playing = false

            // Fires immediately, independent of the narration queue below -
            // used for the lever pull and the reel-spin ambience, which
            // should start right away rather than wait behind anything.
            // Kept in `this.immediate` (by sound name) so a still-playing
            // one - reel-spin can easily outlast the reveal delay - can be
            // cut off explicitly once the outcome is ready to narrate,
            // instead of just hoping the audio file happens to be short
            // enough not to bleed into it.
            this.immediate = {}

            this.handleEvent("play_sound", ({sound}) => {
              if (localStorage.getItem("high_society:sound_muted") === "true") return

              const audio = new Audio(`/audio/slots/${sound}.aac`)
              this.immediate[sound] = audio
              audio.play().catch(() => {})
            })

            // Queued and played one at a time - used for the reveal's
            // narration (a bonus fanfare, then the win/lose sound) so they
            // read as a sequence rather than overlapping.
            this.handleEvent("play_sounds", ({sounds}) => {
              this.stopImmediate("reel-spin")

              if (localStorage.getItem("high_society:sound_muted") === "true") return

              this.queue.push(...sounds)
              this.playNext()
            })
          },
          stopImmediate(sound) {
            const audio = this.immediate[sound]
            if (!audio) return

            audio.pause()
            audio.currentTime = 0
            delete this.immediate[sound]
          },
          playNext() {
            if (this.playing) return

            const name = this.queue.shift()
            if (!name) return

            const audio = new Audio(`/audio/slots/${name}.aac`)
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

  defp free_spins_label(%{free_spins_remaining: n, free_spin_multiplier: mult}),
    do: "#{n} free spins at #{mult}x!"
end
