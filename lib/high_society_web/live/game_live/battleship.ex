defmodule HighSocietyWeb.GameLive.Battleship do
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games.Battleship
  alias HighSociety.Games.BattleshipContext
  alias HighSociety.Money

  import HighSocietyWeb.GameLive.BattleshipComponents

  @wager_options [5_000, 10_000, 25_000, 50_000]

  @impl true
  def mount(_params, _session, socket) do
    game = BattleshipContext.get_active_battleship_game(socket.assigns.current_scope)
    battleship = game && Battleship.from_json(game.battleship)

    socket =
      assign(socket,
        game: game,
        battleship: battleship,
        selected_ship_type: next_unplaced_type(battleship),
        orientation: :horizontal,
        wager_options: @wager_options,
        error: nil,
        last_result: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("start_game", %{"wager" => wager_str}, socket) do
    with {wager, ""} <- Integer.parse(wager_str),
         true <- wager > 0,
         {:ok, game} <-
           BattleshipContext.start_battleship_game(socket.assigns.current_scope, wager) do
      battleship = Battleship.from_json(game.battleship)
      user = Accounts.get_user!(socket.assigns.current_scope.user.id)

      socket =
        assign(socket,
          game: game,
          battleship: battleship,
          selected_ship_type: next_unplaced_type(battleship),
          error: nil,
          last_result: nil,
          current_scope: Scope.for_user(user)
        )

      {:noreply, socket}
    else
      {:error, :insufficient_funds} ->
        {:noreply, assign(socket, error: "You don't have enough balance for that wager.")}

      _ ->
        {:noreply, assign(socket, error: "Enter a valid wager.")}
    end
  end

  def handle_event("select_ship", %{"type" => type}, socket) do
    {:noreply, assign(socket, selected_ship_type: String.to_existing_atom(type))}
  end

  def handle_event("toggle_orientation", _params, socket) do
    orientation = if socket.assigns.orientation == :horizontal, do: :vertical, else: :horizontal
    {:noreply, assign(socket, orientation: orientation)}
  end

  def handle_event(
        "place_ship",
        %{"coord" => _coord},
        %{assigns: %{selected_ship_type: nil}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("place_ship", %{"coord" => coord_str}, socket) do
    {:ok, coord} = Battleship.parse_coord(coord_str)
    ship_type = socket.assigns.selected_ship_type

    case BattleshipContext.place_ship(
           socket.assigns.game,
           ship_type,
           coord,
           socket.assigns.orientation
         ) do
      {:ok, game} ->
        battleship = Battleship.from_json(game.battleship)

        socket =
          assign(socket,
            game: game,
            battleship: battleship,
            selected_ship_type: next_unplaced_type(battleship),
            error: nil
          )

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, error: placement_error_message(reason))}
    end
  end

  def handle_event("randomize", _params, socket) do
    game = BattleshipContext.randomize_player_fleet(socket.assigns.game)

    socket =
      assign(socket,
        game: game,
        battleship: Battleship.from_json(game.battleship),
        selected_ship_type: nil,
        error: nil
      )

    {:noreply, socket}
  end

  def handle_event("clear_placement", _params, socket) do
    game = BattleshipContext.clear_player_fleet(socket.assigns.game)
    battleship = Battleship.from_json(game.battleship)

    socket =
      assign(socket,
        game: game,
        battleship: battleship,
        selected_ship_type: next_unplaced_type(battleship),
        error: nil
      )

    {:noreply, socket}
  end

  def handle_event("ready", _params, socket) do
    case BattleshipContext.ready_up_player(socket.assigns.game) do
      {:ok, game} ->
        {:noreply,
         assign(socket, game: game, battleship: Battleship.from_json(game.battleship), error: nil)}

      {:error, :fleet_incomplete} ->
        {:noreply, assign(socket, error: "Place all 5 ships before you're ready.")}
    end
  end

  def handle_event("fire", %{"coord" => coord_str}, socket) do
    {:ok, coord} = Battleship.parse_coord(coord_str)

    case BattleshipContext.fire(socket.assigns.current_scope, socket.assigns.game, coord) do
      {:ok, game, user, results} ->
        socket =
          socket
          |> assign(
            game: game,
            battleship: Battleship.from_json(game.battleship),
            last_result: results,
            error: nil,
            current_scope: Scope.for_user(user)
          )
          |> push_event("play_sound", %{sound: "artillery-shot"})
          |> push_event("play_sound", %{sound: shot_result_sound(results.player.result)})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("play_again", _params, socket) do
    {:noreply,
     assign(socket,
       game: nil,
       battleship: nil,
       selected_ship_type: nil,
       last_result: nil,
       error: nil
     )}
  end

  def handle_event("claim_starting_chips", _params, socket) do
    case Accounts.claim_battleship_chips(socket.assigns.current_scope.user) do
      {:ok, user} -> {:noreply, assign(socket, current_scope: Scope.for_user(user))}
      {:error, :already_claimed} -> {:noreply, socket}
    end
  end

  defp shot_result_sound(:miss), do: "water-splash"
  defp shot_result_sound(result) when result in [:hit, :sunk], do: "direct-hit"

  defp next_unplaced_type(nil), do: nil

  defp next_unplaced_type(%Battleship{} = battleship) do
    placed = MapSet.new(battleship.player_fleet, & &1.type)
    Enum.find_value(Battleship.ship_specs(), fn spec -> spec.type not in placed && spec.type end)
  end

  defp placement_error_message(:out_of_bounds), do: "That ship would run off the board."
  defp placement_error_message(:overlaps), do: "That overlaps another ship."
  defp placement_error_message(:duplicate_ship_type), do: "That ship is already placed."
  defp placement_error_message(_), do: "Can't place that ship there."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="battleship-screen" class="mx-auto max-w-4xl" phx-hook=".SoundEffects">
        <div class="flex items-center justify-between">
          <div>
            <.link navigate={~p"/"} class="text-sm text-base-content/60 hover:text-base-content">
              &larr; All games
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">Battleship</h1>
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
              :if={is_nil(@current_scope.user.claimed_battleship_chips_at)}
              id="claim-chips-button"
              type="button"
              phx-click="claim_starting_chips"
              class="btn btn-success btn-sm animate-pulse"
            >
              Claim ${Money.format(Accounts.battleship_starting_chip_amount())}
            </button>
            <.link navigate={~p"/games/battleship/lobby"} class="btn btn-ghost btn-sm">
              <.icon name="hero-user-group" class="size-4" /> Play a live opponent
            </.link>
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
          </div>
        </div>

        <p :if={@error} class="mt-4 alert alert-error text-sm">{@error}</p>

        <div :if={is_nil(@game)} class="mt-10 flex flex-col items-center gap-4">
          <p class="text-base-content/70">Choose a wager to start a game against the computer.</p>
          <form phx-submit="start_game" class="flex items-center gap-2">
            <select name="wager" class="select select-bordered">
              <option :for={amount <- @wager_options} value={amount}>${Money.format(amount)}</option>
            </select>
            <button type="submit" class="btn btn-primary">Start game</button>
          </form>
        </div>

        <div :if={@game && @battleship && @battleship.status == :placing_fleets} class="mt-8">
          <h2 class="text-xl font-semibold">Place your fleet</h2>
          <p class="text-sm text-base-content/60">
            Pick a ship, then click a cell on your board. Toggle orientation before placing.
          </p>

          <div class="mt-4 flex flex-wrap items-center gap-2">
            <button
              :for={spec <- Battleship.ship_specs()}
              type="button"
              phx-click="select_ship"
              phx-value-type={spec.type}
              disabled={Enum.any?(@battleship.player_fleet, &(&1.type == spec.type))}
              class={[
                "btn btn-sm",
                @selected_ship_type == spec.type && "btn-primary",
                @selected_ship_type != spec.type && "btn-outline"
              ]}
            >
              {ship_label(spec.type)} ({spec.length})
            </button>

            <button type="button" phx-click="toggle_orientation" class="btn btn-sm btn-ghost">
              <.icon name="hero-arrow-path-rounded-square" class="size-4" />
              {String.capitalize(to_string(@orientation))}
            </button>

            <button type="button" phx-click="randomize" class="btn btn-sm btn-ghost">
              Randomize
            </button>

            <button
              type="button"
              phx-click="clear_placement"
              disabled={@battleship.player_fleet == []}
              class="btn btn-sm btn-ghost text-error"
            >
              <.icon name="hero-x-mark" class="size-4" /> Clear all
            </button>
          </div>

          <div class="mt-6">
            <.board
              id="my-board"
              fleet={@battleship.player_fleet}
              clickable={!is_nil(@selected_ship_type)}
              click_event="place_ship"
              preview_length={@selected_ship_type && Battleship.ship_length(@selected_ship_type)}
              preview_orientation={@orientation}
            />
          </div>

          <button
            type="button"
            phx-click="ready"
            disabled={!Battleship.fleet_complete?(@battleship.player_fleet)}
            class="btn btn-primary mt-6"
          >
            Ready
          </button>
        </div>

        <div
          :if={
            @game && @battleship &&
              @battleship.status in [:player_turn, :opponent_turn, :player_won, :opponent_won]
          }
          class="mt-8"
        >
          <p
            :if={@battleship.status in [:player_turn, :opponent_turn]}
            class="text-center text-lg font-semibold"
          >
            <%= if @battleship.status == :player_turn do %>
              Your turn — fire at the computer's fleet
            <% else %>
              Computer's turn...
            <% end %>
          </p>

          <div :if={@battleship.status == :player_won} class="text-center">
            <p class="text-2xl font-bold text-success">You sank their fleet! 🎉</p>
            <p class="text-base-content/70">You won ${Money.format(@game.payout)}.</p>
          </div>

          <div :if={@battleship.status == :opponent_won} class="text-center">
            <p class="text-2xl font-bold text-error">The computer sank your fleet.</p>
          </div>

          <div :if={@last_result} class="mt-2 text-center text-sm text-base-content/70">
            <span>You: {shot_message(@last_result.player)}</span>
            <span :if={@last_result.computer}> · Computer: {shot_message(@last_result.computer)}</span>
          </div>

          <div class="mt-6 flex flex-col items-center gap-8 sm:flex-row sm:items-start sm:justify-center">
            <div>
              <h3 class="mb-2 text-center text-sm font-semibold uppercase tracking-wide text-base-content/50">
                Your fleet
              </h3>
              <.board
                id="my-board"
                fleet={@battleship.player_fleet}
                shots={@battleship.opponent_shots}
              />
            </div>

            <div>
              <h3 class="mb-2 text-center text-sm font-semibold uppercase tracking-wide text-base-content/50">
                Computer's fleet
              </h3>
              <.board
                id="enemy-board"
                fleet={@battleship.opponent_fleet}
                reveal_only_sunk
                shots={@battleship.player_shots}
                clickable={@battleship.status == :player_turn}
                click_event="fire"
              />
            </div>
          </div>

          <div
            :if={@battleship.status in [:player_won, :opponent_won]}
            class="mt-8 flex justify-center"
          >
            <button type="button" phx-click="play_again" class="btn btn-primary">Play again</button>
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
              "artillery-shot": new Audio("/audio/artillery-shot.aac"),
              "direct-hit": new Audio("/audio/direct-hit.aac"),
              "water-splash": new Audio("/audio/water-splash.aac")
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

  defp ship_label(:carrier), do: "Carrier"
  defp ship_label(:battleship), do: "Battleship"
  defp ship_label(:cruiser), do: "Cruiser"
  defp ship_label(:submarine), do: "Submarine"
  defp ship_label(:destroyer), do: "Destroyer"

  defp shot_message(%{result: :miss}), do: "miss"
  defp shot_message(%{result: :hit}), do: "hit!"
  defp shot_message(%{result: :sunk, ship_type: type}), do: "sunk the #{ship_label(type)}!"
end
