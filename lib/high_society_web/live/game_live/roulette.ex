defmodule HighSocietyWeb.GameLive.Roulette do
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games
  alias HighSociety.Games.Roulette
  alias HighSociety.Tokens

  import HighSocietyWeb.GameLive.RouletteComponents

  # True from the moment a spin is submitted until the winning number is
  # actually revealed (spinning fast, then holding on the landing sound -
  # see `handle_info/2` below) - bets/rebet/a second spin are all locked
  # out for the whole stretch, not just the fast-spin part of it.
  defguardp busy?(spinning?, landing?) when spinning? or landing?

  @chip_values [100, 500, 2_500, 10_000]

  @impl true
  def mount(_params, _session, socket) do
    roulette_game = Games.get_active_roulette_game(socket.assigns.current_scope)

    socket =
      assign(socket,
        roulette_game: roulette_game,
        pending_roulette_game: nil,
        spinning?: false,
        landing?: false,
        pending_bets: %{},
        selected_chip: List.first(@chip_values),
        chip_values: @chip_values,
        error: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("select_chip", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, selected_chip: String.to_integer(amount))}
  end

  def handle_event("place_bet", _params, %{assigns: %{spinning?: s, landing?: l}} = socket)
      when busy?(s, l),
      do: {:noreply, socket}

  def handle_event("place_bet", %{"key" => key}, socket) do
    pending_bets =
      Map.update(
        socket.assigns.pending_bets,
        key,
        socket.assigns.selected_chip,
        &min(&1 + socket.assigns.selected_chip, Roulette.max_bet())
      )

    socket =
      socket
      |> assign(pending_bets: pending_bets, error: nil)
      |> push_event("play_sound", %{sound: "placing-chips"})

    {:noreply, socket}
  end

  def handle_event("clear_bets", _params, %{assigns: %{spinning?: s, landing?: l}} = socket)
      when busy?(s, l),
      do: {:noreply, socket}

  def handle_event("clear_bets", _params, socket) do
    {:noreply, assign(socket, pending_bets: %{}, error: nil)}
  end

  def handle_event("rebet", _params, %{assigns: %{spinning?: s, landing?: l}} = socket)
      when busy?(s, l),
      do: {:noreply, socket}

  def handle_event("rebet", _params, %{assigns: %{roulette_game: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("rebet", _params, socket) do
    pending_bets = Map.new(socket.assigns.roulette_game.bets, &{&1["key"], &1["amount"]})
    {:noreply, assign(socket, pending_bets: pending_bets, error: nil)}
  end

  def handle_event("spin", _params, %{assigns: %{spinning?: s, landing?: l}} = socket)
      when busy?(s, l),
      do: {:noreply, socket}

  def handle_event("spin", _params, socket) do
    case Games.spin_roulette(socket.assigns.current_scope, socket.assigns.pending_bets) do
      {:ok, roulette_game, user} ->
        socket =
          socket
          |> assign(
            pending_roulette_game: roulette_game,
            spinning?: true,
            current_scope: Scope.for_user(user),
            error: nil
          )
          |> push_event("play_sound", %{sound: "ball-spinning"})

        Process.send_after(self(), :start_landing, spin_reveal_delay())

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, error: spin_error_message(reason))}
    end
  end

  def handle_event("claim_roulette_tokens", _params, socket) do
    case Accounts.claim_roulette_tokens(socket.assigns.current_scope.user) do
      {:ok, user} -> {:noreply, assign(socket, current_scope: Scope.for_user(user))}
      {:error, :already_claimed} -> {:noreply, socket}
    end
  end

  # The fast spin stops here and the landing sound starts, but the ball
  # itself stays hidden (see `display_game/1`) for the sound's own
  # duration - without a real bounce animation to justify it, showing the
  # ball already resting while the landing sound is still audibly
  # rattling around read as broken. Only once the sound would have
  # finished (`:reveal_spin`, below) does the wheel/table actually reveal
  # the result.
  @impl true
  def handle_info(:start_landing, socket) do
    socket =
      socket
      |> assign(spinning?: false, landing?: true)
      |> push_event("play_sound", %{sound: "ball-landing"})

    Process.send_after(self(), :reveal_spin, landing_delay())

    {:noreply, socket}
  end

  def handle_info(:reveal_spin, socket) do
    roulette_game = socket.assigns.pending_roulette_game

    socket =
      assign(socket,
        roulette_game: roulette_game,
        pending_roulette_game: nil,
        landing?: false,
        pending_bets: %{}
      )

    {:noreply, socket}
  end

  defp spin_error_message(:no_bets), do: "Place at least one bet before spinning."
  defp spin_error_message(:invalid_bet), do: "That bet isn't valid."

  defp spin_error_message(:bet_too_large),
    do: "Max bet is #{Tokens.format(Roulette.max_bet())} Tokens per spot."

  defp spin_error_message(:insufficient_funds), do: "You don't have enough Tokens for that bet."

  defp spin_reveal_delay,
    do: Application.get_env(:high_society, :roulette_spin_reveal_delay_ms, 3200)

  # How long the landing sound (priv/static/audio/roulette/roulette-ball-
  # landing.aac) actually runs - kept in sync with that file by ear, same
  # as the other paced delays in this app.
  defp landing_delay,
    do: Application.get_env(:high_society, :roulette_landing_delay_ms, 1500)

  defp total_bet(pending_bets), do: pending_bets |> Map.values() |> Enum.sum()

  # The result to actually show - `nil` while a spin is still fast-spinning
  # or holding on the landing sound, even though `roulette_game` itself
  # (the previous spin's row) hasn't been cleared yet at that point.
  defp display_game(%{spinning?: true}), do: nil
  defp display_game(%{landing?: true}), do: nil
  defp display_game(%{roulette_game: game}), do: game

  defp winning_number(nil), do: nil
  defp winning_number(%{winning_number: n}), do: n

  # Unlike `display_game/1`, the wheel is allowed to already know (and
  # animate toward) the real winning number as soon as it's decided -
  # while `landing?`, that's the *upcoming* spin's number, ahead of the
  # table/result text, which stay on the previous spin until the bounce
  # finishes. A real wheel visibly shows where the ball lands before the
  # dealer confirms it on the table, so this mirrors that.
  defp wheel_winning_number(%{landing?: true, pending_roulette_game: %{winning_number: n}}),
    do: n

  defp wheel_winning_number(assigns), do: winning_number(assigns.display_game)

  defp highlighted_cells(nil), do: %{}

  defp highlighted_cells(%{winning_number: n, bets: bets}) do
    won_keys = bets |> Enum.filter(& &1["won"]) |> Enum.map(& &1["key"])
    Map.new(["straight:#{n}" | won_keys], &{&1, true})
  end

  defp color_label(nil), do: nil
  defp color_label(n), do: n |> Roulette.color() |> Atom.to_string() |> String.capitalize()

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :display_game, display_game(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="roulette-screen"
        class="mx-auto max-w-6xl"
        phx-hook=".SoundEffects"
        data-spinning={to_string(@spinning? or @landing?)}
      >
        <div class="flex items-center justify-between">
          <div>
            <.link navigate={~p"/#games"} class="text-sm text-base-content/60 hover:text-base-content">
              &larr; All games
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">Roulette</h1>
          </div>
          <div class="flex items-center gap-3">
            <div class="text-right">
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/50">
                Balance
              </div>
              <.token_balance amount={@current_scope.user.tokens_balance} />
            </div>
            <button
              :if={is_nil(@current_scope.user.claimed_roulette_tokens_at)}
              id="claim-roulette-tokens-button"
              type="button"
              phx-click="claim_roulette_tokens"
              class="btn btn-success btn-sm animate-pulse"
            >
              Claim {Tokens.format(Accounts.roulette_starting_token_amount())} Tokens
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

        <div class="mt-6 flex flex-col items-center gap-6 rounded-[2rem] bg-gradient-to-b from-neutral-800 via-neutral-900 to-black p-4 shadow-2xl ring-2 ring-amber-400/40 sm:p-6 lg:flex-row lg:items-start lg:justify-center">
          <.wheel
            spinning?={@spinning?}
            landing?={@landing?}
            landing_duration_ms={landing_delay()}
            winning_number={wheel_winning_number(assigns)}
          />

          <div class="w-full overflow-x-auto">
            <.betting_table
              pending_bets={@pending_bets}
              highlighted={highlighted_cells(@display_game)}
              winning_number={winning_number(@display_game)}
            />
          </div>
        </div>

        <div :if={@display_game} class="mt-4 min-h-8 text-center">
          <p class="text-lg font-bold text-amber-300">
            Winning number: {@display_game.winning_number} ({color_label(@display_game.winning_number)})
          </p>
          <p :if={@display_game.total_payout > 0} class="text-xl font-bold text-success">
            You won {Tokens.format(@display_game.total_payout)} Tokens!
          </p>
          <p :if={@display_game.total_payout == 0} class="text-base-content/60">
            No win this spin.
          </p>
        </div>

        <div class="mt-8 flex flex-col items-center gap-4">
          <div class="flex flex-wrap items-center justify-center gap-2">
            <button
              :for={chip <- @chip_values}
              id={"chip-#{chip}"}
              type="button"
              phx-click="select_chip"
              phx-value-amount={chip}
              disabled={@spinning? or @landing?}
              class={[
                "flex size-12 items-center justify-center rounded-full border-4 border-dashed text-xs font-bold shadow-md transition-transform hover:-translate-y-0.5",
                chip_color(chip),
                @selected_chip == chip && "ring-2 ring-offset-2 ring-offset-base-100 ring-amber-400"
              ]}
            >
              {Tokens.format(chip)} Tokens
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
              disabled={@spinning? or @landing? or map_size(@pending_bets) == 0}
              class="btn btn-ghost btn-sm"
            >
              Clear bets
            </button>
            <button
              :if={@roulette_game}
              id="rebet-button"
              type="button"
              phx-click="rebet"
              disabled={@spinning? or @landing?}
              class="btn btn-outline btn-sm"
            >
              Rebet
            </button>
          </div>

          <button
            id="spin-button"
            type="button"
            phx-click="spin"
            disabled={@spinning? or @landing? or map_size(@pending_bets) == 0}
            class="btn btn-primary btn-lg px-16"
          >
            {if @spinning? or @landing?, do: "Spinning…", else: "Spin"}
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
            this.current = null

            this.handleEvent("play_sound", ({sound}) => {
              if (localStorage.getItem("high_society:sound_muted") === "true") return

              if (sound === "ball-spinning") {
                this.stopCurrent()
                const audio = new Audio("/audio/roulette/roulette-ball-spinning.aac")
                this.current = audio
                audio.play().catch(() => {})
                return
              }

              if (sound === "ball-landing") {
                this.stopCurrent()
                new Audio("/audio/roulette/roulette-ball-landing.aac").play().catch(() => {})
                return
              }

              new Audio(`/audio/roulette/${sound}.aac`).play().catch(() => {})
            })
          },
          stopCurrent() {
            if (!this.current) return
            this.current.pause()
            this.current.currentTime = 0
            this.current = null
          }
        }
      </script>
    </Layouts.app>
    """
  end

  defp chip_color(100), do: "border-neutral-400 bg-neutral-100 text-neutral-900"
  defp chip_color(500), do: "border-red-300 bg-red-600 text-white"
  defp chip_color(2_500), do: "border-neutral-600 bg-neutral-900 text-white"
  defp chip_color(10_000), do: "border-amber-300 bg-amber-500 text-amber-950"
end
