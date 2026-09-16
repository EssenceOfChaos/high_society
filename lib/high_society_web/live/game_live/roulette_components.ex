defmodule HighSocietyWeb.GameLive.RouletteComponents do
  @moduledoc """
  Shared Roulette rendering: the spinning wheel and the felt betting table.

  Every genuinely per-instance placement (wheel gradient, pocket label
  angles, the ball's resting angle, each table cell's grid position) is
  applied via `phx-hook=".InlineStyle"` + `data-style` rather than a plain
  `style=""` attribute - the app's CSP has no `unsafe-inline` for
  `style-src` and doesn't support nonces on style *attributes* (only
  `<style>` elements), so an inline `style=""` would silently stop
  applying in production. `data-*` attributes aren't governed by
  `style-src` at all, and the hook (defined once, in
  `HighSocietyWeb.GameLive.Roulette`) applies them via `el.style.cssText`,
  which is a plain CSSOM mutation the CSP doesn't see either.
  """
  use Phoenix.Component

  alias HighSociety.Games.Roulette
  alias HighSociety.Tokens

  # The wheel's rendered size never changes with viewport, so its radius is
  # a fixed constant - notably shared with the `.roulette-ball-spin`
  # keyframe's hardcoded -142px in app.css, which must stay in sync with it.
  @wheel_size 300
  @wheel_radius @wheel_size / 2 - 14

  # The bounce sequence's waypoints, in pockets away from the true winner
  # (converted to degrees at render time), and each step's share of the
  # total landing duration - decreasing amplitude, increasing dwell time,
  # so it reads as the ball losing energy and settling rather than
  # bouncing at a constant rate. The last entry is always 0 pockets away
  # (the real winner), so the sequence necessarily ends exactly where the
  # settled ball (rendered separately, once `landing?` ends) will be.
  @bounce_offsets_pockets [6, -4, 3, -2, 1, 0]
  @bounce_weights [1.0, 1.0, 1.2, 1.4, 1.7, 2.2]

  attr :spinning?, :boolean, default: false
  attr :landing?, :boolean, default: false
  attr :landing_duration_ms, :integer, default: 1500
  attr :winning_number, :integer, default: nil

  @doc """
  The wheel: a colored disc (one conic-gradient wedge per pocket, in real
  wheel order) with a ball that's in one of three states - spinning fast
  indefinitely (`spinning?`), bouncing pocket-to-pocket down to
  `winning_number` over `landing_duration_ms` (`landing?`), or sitting at
  rest on it (neither).
  """
  def wheel(assigns) do
    assigns =
      assigns
      |> assign(:gradient, wheel_gradient())
      |> assign(:ball_angle, ball_angle(assigns.winning_number))
      |> assign(:wheel_radius, @wheel_radius)
      |> assign(:bounce_waypoints_json, bounce_waypoints_json(assigns))

    ~H"""
    <div class="relative mx-auto size-[300px] shrink-0">
      <div
        id="roulette-wheel-disc"
        class="absolute inset-0 rounded-full shadow-[inset_0_0_20px_rgba(0,0,0,0.6)] ring-4 ring-amber-400/60"
        phx-hook=".InlineStyle"
        data-style={"background: #{@gradient}"}
      >
        <span
          :for={n <- Roulette.wheel_order()}
          id={"wheel-pocket-label-#{n}"}
          class="absolute top-1/2 left-1/2 text-[11px] font-bold text-white/90"
          phx-hook=".InlineStyle"
          data-style={"transform: translate(-50%, -50%) rotate(#{pocket_center_angle(n)}deg) translateY(-#{@wheel_radius - 8}px) rotate(#{-pocket_center_angle(n)}deg)"}
        >
          {n}
        </span>
      </div>

      <div class="absolute inset-[18%] rounded-full bg-gradient-to-br from-amber-200 via-amber-400 to-amber-600 shadow-inner" />
      <div class="absolute inset-[38%] rounded-full bg-gradient-to-br from-neutral-700 to-neutral-900 shadow-lg" />

      <div
        :if={@spinning?}
        class="roulette-ball-spin absolute top-1/2 left-1/2 size-3 rounded-full bg-white shadow-[0_0_6px_2px_rgba(255,255,255,0.8)]"
      />
      <div
        :if={@landing? && @winning_number}
        id="roulette-ball-bounce"
        class="absolute top-1/2 left-1/2 size-3 rounded-full bg-white shadow-[0_0_6px_2px_rgba(255,255,255,0.8)]"
        phx-hook=".RouletteBallBounce"
        data-radius={@wheel_radius + 6}
        data-waypoints={@bounce_waypoints_json}
      />
      <div
        :if={!@spinning? && !@landing? && @winning_number}
        id="roulette-ball"
        class="absolute top-1/2 left-1/2 size-3 rounded-full bg-white shadow-[0_0_6px_2px_rgba(255,255,255,0.8)]"
        phx-hook=".InlineStyle"
        data-style={"transform: translate(-50%, -50%) rotate(#{@ball_angle}deg) translateY(-#{@wheel_radius + 6}px)"}
      />
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".InlineStyle">
      export default {
        mounted() { this.el.style.cssText = this.el.dataset.style },
        updated() { this.el.style.cssText = this.el.dataset.style }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".RouletteBallBounce">
      export default {
        mounted() {
          const radius = Number(this.el.dataset.radius)
          const waypoints = JSON.parse(this.el.dataset.waypoints || "[]")
          const base = (angle) => `translate(-50%, -50%) rotate(${angle}deg) translateY(-${radius}px)`

          // No prior transform to animate from (this element is created
          // fresh for every landing phase) - set an arbitrary starting
          // angle with no transition first, so the very first waypoint
          // still has something to visibly animate away from instead of
          // popping straight to it.
          this.el.style.transition = "none"
          this.el.style.transform = base(0)
          void this.el.offsetWidth

          let i = 0
          const step = () => {
            if (i >= waypoints.length) return
            const {angle, duration} = waypoints[i]
            this.el.style.transition = `transform ${duration}ms cubic-bezier(0.22, 0.61, 0.36, 1)`
            this.el.style.transform = base(angle)
            i += 1
            this.timer = setTimeout(step, duration)
          }
          step()
        },
        destroyed() {
          if (this.timer) clearTimeout(this.timer)
        }
      }
    </script>
    """
  end

  defp wheel_gradient do
    step = 360 / 37

    {stops, _} =
      Roulette.wheel_order()
      |> Enum.reduce({[], 0.0}, fn n, {acc, start} ->
        finish = start + step
        stop = "#{wedge_color(n)} #{fmt(start)}deg #{fmt(finish)}deg"
        {[stop | acc], finish}
      end)

    "conic-gradient(#{stops |> Enum.reverse() |> Enum.join(", ")})"
  end

  defp wedge_color(n) do
    case Roulette.color(n) do
      :green -> "#059669"
      :red -> "#dc2626"
      :black -> "#18181b"
    end
  end

  defp fmt(f), do: :erlang.float_to_binary(f, decimals: 3)

  # The angle of the *middle* of pocket `n`'s wedge (each wedge is
  # 360/37deg wide) - not its leading edge, so both the number label and
  # the resting ball sit centered in their color band instead of hugging
  # the boundary with the next pocket.
  defp pocket_center_angle(n) do
    step = 360 / 37
    index = Enum.find_index(Roulette.wheel_order(), &(&1 == n))
    index * step + step / 2
  end

  defp ball_angle(nil), do: 0
  defp ball_angle(n), do: pocket_center_angle(n)

  # The bounce sequence for the `.RouletteBallBounce` hook to step
  # through, JSON-encoded since it's carried over as a `data-*` attribute
  # (see the moduledoc on why this can't just be a `style=""` attribute).
  # Computed here rather than client-side so the sequence always ends
  # exactly on the server-decided winning pocket, same as everything else
  # about the result.
  defp bounce_waypoints_json(%{landing?: true, winning_number: n, landing_duration_ms: total_ms})
       when not is_nil(n) do
    final_angle = pocket_center_angle(n)
    step_deg = 360 / 37
    total_weight = Enum.sum(@bounce_weights)

    @bounce_offsets_pockets
    |> Enum.zip(@bounce_weights)
    |> Enum.map(fn {offset, weight} ->
      %{angle: final_angle + offset * step_deg, duration: round(total_ms * weight / total_weight)}
    end)
    |> Jason.encode!()
  end

  defp bounce_waypoints_json(_assigns), do: "[]"

  attr :pending_bets, :map, required: true
  attr :highlighted, :map, default: %{}
  attr :winning_number, :integer, default: nil

  @doc """
  The felt betting table: 0 plus the 1-36 grid (colored to match the wheel),
  the three column ("2 to 1") spots, the three dozens, and the six even-
  money outside bets - laid out exactly like a real single-zero table.
  """
  def betting_table(assigns) do
    ~H"""
    <div
      id="roulette-table"
      class="roulette-table-grid grid gap-[3px] rounded-box bg-emerald-900 p-2 ring-2 ring-amber-400/40 sm:gap-1"
    >
      <.cell
        key="straight:0"
        label="0"
        grid_style="grid-column: 1; grid-row: 1 / span 3;"
        color={:green}
        pending_bets={@pending_bets}
        highlighted?={Map.get(@highlighted, "straight:0", false)}
      />

      <.cell
        :for={{n, col, row} <- number_positions()}
        key={"straight:#{n}"}
        label={Integer.to_string(n)}
        grid_style={"grid-column: #{col}; grid-row: #{row};"}
        color={Roulette.color(n)}
        pending_bets={@pending_bets}
        highlighted?={Map.get(@highlighted, "straight:#{n}", false)}
      />

      <.cell
        :for={row <- 1..3}
        key={"column:#{4 - row}"}
        label="2 to 1"
        grid_style={"grid-column: 14; grid-row: #{row};"}
        color={:felt}
        pending_bets={@pending_bets}
        highlighted?={Map.get(@highlighted, "column:#{4 - row}", false)}
      />

      <.cell
        :for={{d, col} <- [{1, 2}, {2, 6}, {3, 10}]}
        key={"dozen:#{d}"}
        label={dozen_label(d)}
        grid_style={"grid-column: #{col} / span 4; grid-row: 4;"}
        color={:felt}
        pending_bets={@pending_bets}
        highlighted?={Map.get(@highlighted, "dozen:#{d}", false)}
      />

      <.cell
        :for={{key, label, col} <- outside_bets()}
        key={key}
        label={label}
        grid_style={"grid-column: #{col} / span 2; grid-row: 5;"}
        color={outside_bet_color(key)}
        pending_bets={@pending_bets}
        highlighted?={Map.get(@highlighted, key, false)}
      />
    </div>
    """
  end

  # column c, row r (0-indexed) -> number = c*3 + (3 - r), matching a real
  # table's left-to-right, bottom-to-top layout (row 0 is the top row).
  defp number_positions do
    for col_index <- 0..11, row_index <- 0..2 do
      {col_index * 3 + (3 - row_index), col_index + 2, row_index + 1}
    end
  end

  defp dozen_label(1), do: "1st 12"
  defp dozen_label(2), do: "2nd 12"
  defp dozen_label(3), do: "3rd 12"

  defp outside_bets do
    [
      {"low", "1 to 18", 2},
      {"even", "EVEN", 4},
      {"red", "♦", 6},
      {"black", "♦", 8},
      {"odd", "ODD", 10},
      {"high", "19 to 36", 12}
    ]
  end

  defp outside_bet_color("red"), do: :red
  defp outside_bet_color("black"), do: :black
  defp outside_bet_color(_key), do: :felt

  attr :key, :string, required: true
  attr :label, :string, required: true
  attr :grid_style, :string, required: true
  attr :color, :atom, required: true
  attr :pending_bets, :map, required: true
  attr :highlighted?, :boolean, default: false

  defp cell(assigns) do
    assigns =
      assigns
      |> assign(:amount, Map.get(assigns.pending_bets, assigns.key, 0))
      |> assign(:dom_id, "bet-cell-#{String.replace(assigns.key, ":", "-")}")

    ~H"""
    <button
      id={@dom_id}
      type="button"
      phx-click="place_bet"
      phx-value-key={@key}
      phx-hook=".InlineStyle"
      data-style={@grid_style}
      class={[
        "relative flex items-center justify-center rounded-sm text-sm font-bold transition-all sm:text-base",
        cell_color_class(@color),
        @highlighted? && "ring-4 ring-amber-300 z-10"
      ]}
    >
      {@label}
      <span
        :if={@amount > 0}
        class="absolute inset-0 flex items-center justify-center rounded-full"
      >
        <span class="flex size-7 items-center justify-center rounded-full border-2 border-white bg-amber-500/90 text-[11px] text-white shadow sm:size-8">
          {Tokens.format(@amount)}
        </span>
      </span>
    </button>
    """
  end

  defp cell_color_class(:red), do: "bg-red-600 text-white hover:bg-red-500"
  defp cell_color_class(:black), do: "bg-neutral-900 text-white hover:bg-neutral-800"
  defp cell_color_class(:green), do: "bg-emerald-600 text-white hover:bg-emerald-500"

  defp cell_color_class(:felt),
    do: "bg-emerald-800 text-amber-100 hover:bg-emerald-700 border border-amber-400/30"
end
