defmodule HighSocietyWeb.GameLive.BattleshipMatch do
  use HighSocietyWeb, :live_view

  alias HighSociety.Games.Battleship
  alias HighSociety.Games.BattleshipMatch

  import HighSocietyWeb.GameLive.BattleshipComponents

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case fetch_view(slug) do
      {:ok, view} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(HighSociety.PubSub, BattleshipMatch.topic(slug))
          HighSocietyWeb.Presence.track(self(), presence_topic(slug), socket.assigns.current_scope.user.id, %{})
          Phoenix.PubSub.subscribe(HighSociety.PubSub, presence_topic(slug))
        end

        socket =
          assign(socket,
            slug: slug,
            view: view,
            watching: watching_count(slug),
            selected_ship_type: nil,
            orientation: :horizontal,
            error: nil
          )

        {:ok, socket}

      :not_found ->
        {:ok,
         socket
         |> put_flash(:info, "That match has ended or doesn't exist.")
         |> push_navigate(to: ~p"/games/battleship/lobby")}
    end
  end

  defp fetch_view(slug) do
    {:ok, BattleshipMatch.get_state(slug)}
  catch
    :exit, _ -> :not_found
  end

  defp presence_topic(slug), do: "battleship_match_watchers:#{slug}"

  defp watching_count(slug), do: slug |> presence_topic() |> HighSocietyWeb.Presence.list() |> map_size()

  @impl true
  def handle_info({:battleship_match_updated, %{status: :cancelled}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "That match was cancelled.")
     |> push_navigate(to: ~p"/games/battleship/lobby")}
  end

  def handle_info({:battleship_match_updated, view}, socket) do
    socket = assign(socket, view: view, selected_ship_type: reset_selected(socket, view))
    {:noreply, socket}
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, watching: watching_count(socket.assigns.slug))}
  end

  defp reset_selected(socket, view) do
    user_id = socket.assigns.current_scope.user.id
    perspective = perspective(view, user_id)
    if Battleship.fleet_complete?(perspective.my_fleet), do: nil, else: socket.assigns.selected_ship_type
  end

  @impl true
  def handle_event("join", _params, socket) do
    case BattleshipMatch.join(socket.assigns.slug, socket.assigns.current_scope.user) do
      {:ok, view} -> {:noreply, assign(socket, view: view, error: nil)}
      {:error, reason} -> {:noreply, assign(socket, error: join_error_message(reason))}
    end
  end

  def handle_event("cancel", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case BattleshipMatch.cancel(socket.assigns.slug, user_id) do
      {:ok, _view} ->
        {:noreply,
         socket
         |> put_flash(:info, "Match cancelled - your wager was refunded.")
         |> push_navigate(to: ~p"/games/battleship/lobby")}

      {:error, _reason} ->
        {:noreply, assign(socket, error: "Couldn't cancel this match.")}
    end
  end

  def handle_event("select_ship", %{"type" => type}, socket) do
    {:noreply, assign(socket, selected_ship_type: String.to_existing_atom(type))}
  end

  def handle_event("toggle_orientation", _params, socket) do
    orientation = if socket.assigns.orientation == :horizontal, do: :vertical, else: :horizontal
    {:noreply, assign(socket, orientation: orientation)}
  end

  def handle_event("place_ship", %{"coord" => _coord}, %{assigns: %{selected_ship_type: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("place_ship", %{"coord" => coord_str}, socket) do
    {:ok, coord} = Battleship.parse_coord(coord_str)
    user_id = socket.assigns.current_scope.user.id
    ship_type = socket.assigns.selected_ship_type

    case BattleshipMatch.place_ship(socket.assigns.slug, user_id, ship_type, coord, socket.assigns.orientation) do
      {:ok, view} ->
        perspective = perspective(view, user_id)
        next_type = next_unplaced_type(perspective.my_fleet)
        {:noreply, assign(socket, view: view, selected_ship_type: next_type, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: placement_error_message(reason))}
    end
  end

  def handle_event("randomize", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    {:ok, view} = BattleshipMatch.randomize_fleet(socket.assigns.slug, user_id)
    {:noreply, assign(socket, view: view, selected_ship_type: nil, error: nil)}
  end

  def handle_event("clear_placement", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    {:ok, view} = BattleshipMatch.clear_fleet(socket.assigns.slug, user_id)
    perspective = perspective(view, user_id)

    socket =
      assign(socket,
        view: view,
        selected_ship_type: next_unplaced_type(perspective.my_fleet),
        error: nil
      )

    {:noreply, socket}
  end

  def handle_event("ready", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case BattleshipMatch.ready_up(socket.assigns.slug, user_id) do
      {:ok, view} -> {:noreply, assign(socket, view: view, error: nil)}
      {:error, :fleet_incomplete} -> {:noreply, assign(socket, error: "Place all 5 ships before you're ready.")}
    end
  end

  def handle_event("fire", %{"coord" => coord_str}, socket) do
    {:ok, coord} = Battleship.parse_coord(coord_str)
    user_id = socket.assigns.current_scope.user.id

    case BattleshipMatch.fire(socket.assigns.slug, user_id, coord) do
      {:ok, view} ->
        socket =
          socket
          |> assign(view: view, error: nil)
          |> push_event("play_sound", %{sound: "artillery-shot"})
          |> push_event("play_sound", %{sound: shot_result_sound(view.last_shot.result.result)})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("forfeit", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    {:ok, view} = BattleshipMatch.forfeit(socket.assigns.slug, user_id)
    {:noreply, assign(socket, view: view, error: nil)}
  end

  defp join_error_message(:match_full), do: "That match is already full."
  defp join_error_message(:already_seated), do: "You're already in this match."
  defp join_error_message(:insufficient_funds), do: "You don't have enough balance to match that wager."

  defp placement_error_message(:out_of_bounds), do: "That ship would run off the board."
  defp placement_error_message(:overlaps), do: "That overlaps another ship."
  defp placement_error_message(:duplicate_ship_type), do: "That ship is already placed."
  defp placement_error_message(_), do: "Can't place that ship there."

  defp next_unplaced_type(fleet) do
    placed = MapSet.new(fleet, & &1.type)
    Enum.find_value(Battleship.ship_specs(), fn spec -> spec.type not in placed && spec.type end)
  end

  # Adapts the match's canonical (seat 0 = `:player`, seat 1 = `:opponent`)
  # view into "me" vs. "the opponent" for whichever seat `user_id` occupies
  # - or an empty, non-interactive perspective for a spectator/not-yet-joined
  # visitor.
  defp perspective(view, user_id) do
    cond do
      view.seats[0] && view.seats[0].user_id == user_id -> build_perspective(view, 0)
      view.seats[1] && view.seats[1].user_id == user_id -> build_perspective(view, 1)
      true -> %{seat: nil, my_fleet: [], my_received: %{}, enemy_fleet: [], my_fired: %{}, my_turn?: false}
    end
  end

  defp build_perspective(%{battleship: nil}, seat) do
    %{seat: seat, my_fleet: [], my_received: %{}, enemy_fleet: [], my_fired: %{}, my_turn?: false}
  end

  defp build_perspective(%{battleship: battleship, status: status}, 0) do
    %{
      seat: 0,
      my_fleet: battleship.player_fleet,
      my_received: battleship.opponent_shots,
      enemy_fleet: battleship.opponent_fleet,
      my_fired: battleship.player_shots,
      my_turn?: status == :player_turn
    }
  end

  defp build_perspective(%{battleship: battleship, status: status}, 1) do
    %{
      seat: 1,
      my_fleet: battleship.opponent_fleet,
      my_received: battleship.player_shots,
      enemy_fleet: battleship.player_fleet,
      my_fired: battleship.opponent_shots,
      my_turn?: status == :opponent_turn
    }
  end

  defp opponent_username(view, my_seat) do
    other_seat = if my_seat == 0, do: 1, else: 0
    seat = view.seats[other_seat]
    (seat && seat.username) || "your opponent"
  end

  defp won_status_for_seat(0), do: :player_won
  defp won_status_for_seat(1), do: :opponent_won
  defp won_status_for_seat(_), do: nil

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :p, perspective(assigns.view, assigns.current_scope.user.id))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="battleship-match-screen" class="mx-auto max-w-4xl" phx-hook=".SoundEffects">
        <div class="flex items-center justify-between">
          <div>
            <.link navigate={~p"/games/battleship/lobby"} class="text-sm text-base-content/60 hover:text-base-content">
              &larr; All matches
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">Battleship — ${@view.wager} match</h1>
          </div>
          <div class="flex items-center gap-3">
            <span class="flex items-center gap-1.5 rounded-full bg-base-200 px-3 py-1 text-sm font-semibold">
              <.icon name="hero-eye" class="size-4" /> {@watching} watching
            </span>
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

        <div :if={@view.status == :waiting_for_opponent} class="mt-10 text-center">
          <p class="text-base-content/70">Waiting for an opponent to join...</p>
          <button
            :if={is_nil(@p.seat)}
            type="button"
            phx-click="join"
            class="btn btn-primary mt-4"
          >
            Join this match for ${@view.wager}
          </button>
          <div :if={@p.seat == 0}>
            <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm mt-4 text-error">
              Cancel match
            </button>
          </div>
        </div>

        <div :if={@view.status == :placing_fleets} class="mt-8">
          <div :if={@p.seat} id="placement">
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
                disabled={Enum.any?(@p.my_fleet, &(&1.type == spec.type))}
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

              <button type="button" phx-click="randomize" class="btn btn-sm btn-ghost">Randomize</button>

              <button
                type="button"
                phx-click="clear_placement"
                disabled={@p.my_fleet == []}
                class="btn btn-sm btn-ghost text-error"
              >
                <.icon name="hero-x-mark" class="size-4" /> Clear all
              </button>
            </div>

            <div class="mt-6">
              <.board
                id="my-board"
                fleet={@p.my_fleet}
                clickable={!is_nil(@selected_ship_type)}
                click_event="place_ship"
                preview_length={@selected_ship_type && Battleship.ship_length(@selected_ship_type)}
                preview_orientation={@orientation}
              />
            </div>

            <button
              type="button"
              phx-click="ready"
              disabled={!Battleship.fleet_complete?(@p.my_fleet)}
              class="btn btn-primary mt-6"
            >
              Ready
            </button>
          </div>

          <p :if={is_nil(@p.seat)} class="text-center text-base-content/70">
            Both seats are placing their fleets.
          </p>
        </div>

        <div
          :if={@view.status in [:player_turn, :opponent_turn, :player_won, :opponent_won]}
          class="mt-8"
        >
          <p :if={@view.status in [:player_turn, :opponent_turn] && @p.seat} class="text-center text-lg font-semibold">
            <%= if @p.my_turn? do %>
              Your turn — fire at {opponent_username(@view, @p.seat)}'s fleet
            <% else %>
              Waiting on {opponent_username(@view, @p.seat)}...
            <% end %>
          </p>

          <div :if={@p.seat && @view.status == won_status_for_seat(@p.seat)} class="text-center">
            <p class="text-2xl font-bold text-success">You sank their fleet! 🎉</p>
          </div>

          <div
            :if={
              @p.seat && @view.status in [:player_won, :opponent_won] &&
                @view.status != won_status_for_seat(@p.seat)
            }
            class="text-center"
          >
            <p class="text-2xl font-bold text-error">Your fleet was sunk.</p>
          </div>

          <div :if={is_nil(@p.seat) && @view.status in [:player_won, :opponent_won]} class="text-center">
            <p class="text-2xl font-bold">Match over.</p>
          </div>

          <div :if={@view.last_shot} class="mt-2 text-center text-sm text-base-content/70">
            {shot_message(@view.last_shot)}
          </div>

          <div class="mt-6 flex flex-col items-center gap-8 sm:flex-row sm:items-start sm:justify-center">
            <div>
              <h3 class="mb-2 text-center text-sm font-semibold uppercase tracking-wide text-base-content/50">
                Your fleet
              </h3>
              <.board id="my-board" fleet={@p.my_fleet} shots={@p.my_received} />
            </div>

            <div>
              <h3 class="mb-2 text-center text-sm font-semibold uppercase tracking-wide text-base-content/50">
                {opponent_username(@view, @p.seat || -1)}'s fleet
              </h3>
              <.board
                id="enemy-board"
                fleet={@p.enemy_fleet}
                reveal_only_sunk
                shots={@p.my_fired}
                clickable={@p.my_turn?}
                click_event="fire"
              />
            </div>
          </div>

          <div
            :if={@p.seat && @view.status in [:player_turn, :opponent_turn]}
            class="mt-8 flex justify-center"
          >
            <button type="button" phx-click="forfeit" class="btn btn-ghost btn-sm text-error">
              Forfeit match
            </button>
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

  defp shot_message(%{side: side, coord: coord, result: %{result: :miss}}),
    do: "#{side_label(side)} fired at #{coord} — miss."

  defp shot_message(%{side: side, coord: coord, result: %{result: :hit}}),
    do: "#{side_label(side)} fired at #{coord} — hit!"

  defp shot_message(%{side: side, coord: coord, result: %{result: :sunk, ship_type: type}}),
    do: "#{side_label(side)} fired at #{coord} — sank the #{ship_label(type)}!"

  defp side_label(:player), do: "Seat 1"
  defp side_label(:opponent), do: "Seat 2"

  defp shot_result_sound(:miss), do: "water-splash"
  defp shot_result_sound(result) when result in [:hit, :sunk], do: "direct-hit"
end
