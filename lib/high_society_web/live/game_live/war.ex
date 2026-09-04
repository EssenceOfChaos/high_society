defmodule HighSocietyWeb.GameLive.War do
  use HighSocietyWeb, :live_view

  alias HighSociety.Games

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
    war_declared? = war_game.last_round["pending?"] || false

    socket =
      socket
      |> assign(war_game: war_game, warring?: warring?)
      |> push_event("play_sound", %{sound: "deal"})

    socket =
      if war_declared? do
        push_event(socket, "play_sound", %{sound: "war"})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("new_game", _params, socket) do
    war_game = Games.start_war_game(socket.assigns.current_scope)
    {:noreply, assign(socket, war_game: war_game, warring?: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="war-screen" class="mx-auto max-w-3xl" phx-hook=".SoundEffects">
        <div class="flex items-center justify-between">
          <div>
            <.link navigate={~p"/"} class="text-sm text-base-content/60 hover:text-base-content">
              &larr; All games
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">War</h1>
          </div>
          <div class="flex items-center gap-2">
            <button
              id="sound-toggle-button"
              type="button"
              phx-hook=".SoundToggle"
              class="btn btn-ghost btn-sm"
              aria-label="Toggle sound"
              aria-pressed="true"
            >
              <.icon name="hero-speaker-wave" class="size-4 sound-on-icon" />
              <.icon name="hero-speaker-x-mark" class="size-4 sound-off-icon hidden" />
            </button>
            <button
              :if={@war_game}
              id="new-game-button"
              phx-click="new_game"
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-arrow-path" class="size-4" /> New game
            </button>
          </div>
        </div>

        <div :if={!@war_game} class="mt-16 flex justify-center">
          <span class="loading loading-spinner loading-lg" />
        </div>

        <.status_bar
          :if={@war_game}
          player_count={length(@war_game.player_deck)}
          computer_count={length(@war_game.computer_deck)}
        />

        <div
          :if={@war_game}
          id="war-table"
          class={[
            "mt-8 rounded-2xl transition-colors duration-500",
            war_pending?(@war_game) &&
              "-mx-4 border-4 border-error bg-error/10 p-4 shadow-lg shadow-error/20"
          ]}
        >
          <div class="grid grid-cols-2 gap-6">
            <.pile label="You" count={length(@war_game.player_deck)} align="left" />
            <.pile label="Computer" count={length(@war_game.computer_deck)} align="right" />
          </div>

          <div :if={war_pending?(@war_game)} class="mt-6 text-center">
            <p class="animate-pulse text-4xl font-black uppercase tracking-widest text-error">
              ⚔️ War! ⚔️
            </p>
            <p class="mt-1 text-sm font-medium text-error/80">
              Three cards burned each. Flip the tiebreaker to see who takes the pot.
            </p>
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
              <.card_face card={last_card(@war_game, :player_card)} pending={war_pending?(@war_game)} />
            </div>
            <div class="flex flex-col items-center gap-1">
              <span
                :if={war_round?(@war_game)}
                class="text-xs font-semibold uppercase tracking-wide text-warning"
              >
                Tiebreaker
              </span>
              <.card_face
                card={last_card(@war_game, :computer_card)}
                pending={war_pending?(@war_game)}
              />
            </div>
          </div>

          <div class="mt-6 text-center min-h-8">
            <p
              :if={
                @war_game.last_round && @war_game.status == "in_progress" && !war_pending?(@war_game)
              }
              class={[
                @warring? && "font-bold text-warning text-lg",
                !@warring? && "text-base-content/70"
              ]}
            >
              {round_message(@war_game.last_round)}
            </p>
          </div>

          <div class="mt-6 flex justify-center">
            <button
              :if={@war_game.status == "in_progress" && !war_pending?(@war_game)}
              id="flip-button"
              phx-click="flip"
              class="btn btn-primary btn-lg px-12"
            >
              Flip
            </button>

            <button
              :if={@war_game.status == "in_progress" && war_pending?(@war_game)}
              id="flip-tiebreaker-button"
              phx-click="flip"
              class="btn btn-error btn-lg animate-pulse px-12"
            >
              ⚔️ Flip tiebreaker
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
              war: new Audio("/audio/war-drums.wav")
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

  attr :player_count, :integer, required: true
  attr :computer_count, :integer, required: true

  defp status_bar(assigns) do
    total = assigns.player_count + assigns.computer_count
    player_pct = if total > 0, do: assigns.player_count / total * 100, else: 50.0

    assigns = assign(assigns, :player_pct, player_pct)

    ~H"""
    <div id="status-bar" class="mt-6">
      <div class="flex items-center justify-between text-xs font-medium text-base-content/60">
        <span>You — {@player_count} cards</span>
        <span>Computer — {@computer_count} cards</span>
      </div>
      <div class="mt-1.5 flex h-3 w-full overflow-hidden rounded-full bg-base-300">
        <div
          id="status-bar-fill"
          class="h-full bg-primary transition-all duration-500 ease-out"
          phx-hook=".InlineStyle"
          data-style={"width: #{@player_pct}%"}
        />
        <div class="h-full flex-1 bg-error/70 transition-all duration-500 ease-out" />
      </div>
      <p class="mt-1.5 text-center text-xs font-semibold uppercase tracking-wide text-base-content/50">
        {status_message(@player_pct)}
      </p>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".InlineStyle">
      export default {
        mounted() { this.el.style.cssText = this.el.dataset.style },
        updated() { this.el.style.cssText = this.el.dataset.style }
      }
    </script>
    """
  end

  defp status_message(pct) when pct == 100, do: "You've won the game!"
  defp status_message(pct) when pct >= 90, do: "You're close to winning"
  defp status_message(pct) when pct >= 65, do: "You're dominating"
  defp status_message(pct) when pct >= 55, do: "You're ahead"
  defp status_message(pct) when pct > 45, do: "It's neck and neck"
  defp status_message(pct) when pct > 35, do: "You're behind"
  defp status_message(pct) when pct > 10, do: "You're in trouble"
  defp status_message(pct) when pct == 0, do: "You've lost the game"
  defp status_message(_pct), do: "You're close to losing"

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

  defp last_card(%{last_round: nil}, _key), do: nil
  defp last_card(%{last_round: last_round}, key), do: Map.get(last_round, Atom.to_string(key))

  defp ties(%{last_round: nil}), do: []
  defp ties(%{last_round: last_round}), do: Map.get(last_round, "ties") || []

  defp war_round?(%{last_round: nil}), do: false
  defp war_round?(%{last_round: last_round}), do: Map.get(last_round, "war?") || false

  defp war_pending?(%{last_round: nil}), do: false
  defp war_pending?(%{last_round: last_round}), do: Map.get(last_round, "pending?") || false

  defp round_message(%{"winner" => "player", "cards_won" => n, "war?" => true}),
    do: "WAR! Your tiebreaker won — you took #{n} cards total."

  defp round_message(%{"winner" => "computer", "cards_won" => n, "war?" => true}),
    do: "WAR! The computer's tiebreaker won — it took #{n} cards total."

  defp round_message(%{"winner" => "player", "cards_won" => n}),
    do: "You won that round and took #{n} cards."

  defp round_message(%{"winner" => "computer", "cards_won" => n}),
    do: "The computer won that round and took #{n} cards."
end
