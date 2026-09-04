defmodule HighSocietyWeb.GameLive.BattleshipComponents do
  @moduledoc """
  Shared Battleship board rendering, used by both the vs-computer
  (`HighSocietyWeb.GameLive.Battleship`) and live-match
  (`HighSocietyWeb.GameLive.BattleshipMatch`) screens - the same 10x10
  grid renders either a player's own fleet (every ship visible) or a
  tracking grid of shots fired at an opponent (`reveal_only_sunk: true`
  keeps anything but a fully-sunk ship hidden).

  Ships render as inline SVG bow/hull/stern segments (one shape per
  occupied cell, based on that cell's position within the ship) rather
  than a flat color block, so a placed ship reads as an actual boat
  silhouette instead of a gray rectangle. There's still no external
  image asset - these are small, hand-drawn paths that stay legible at
  the board's actual cell size.
  """
  use Phoenix.Component

  alias HighSociety.Games.Battleship

  @columns ~w(A B C D E F G H I J)
  # Kept in sync by hand with the `grid-cols-[...]` literal below - Tailwind's
  # class scanner needs the literal utility name, so it can't read this value.
  @board_size Battleship.board_size()

  @hull_color "#778da9"
  @sunk_color "#4a5568"

  attr :id, :string, required: true
  attr :fleet, :list, default: []
  attr :shots, :map, default: %{}
  attr :reveal_only_sunk, :boolean, default: false
  attr :clickable, :boolean, default: false
  attr :click_event, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :preview_length, :integer, default: nil
  attr :preview_orientation, :atom, default: :horizontal

  def board(assigns) do
    ~H"""
    <div
      id={@id}
      class="inline-grid grid-cols-[1.25rem_repeat(10,1.75rem)]"
      phx-hook=".PlacementPreview"
      data-preview-length={@preview_length}
      data-orientation={@preview_orientation}
    >
      <div />
      <div
        :for={col <- 0..(board_size() - 1)}
        class="text-center text-xs font-semibold text-base-content/50"
      >
        {column_letter(col)}
      </div>

      <%= for row <- 0..(board_size() - 1) do %>
        <div class="flex items-center justify-center text-xs font-semibold text-base-content/50">
          {row + 1}
        </div>
        <button
          :for={col <- 0..(board_size() - 1)}
          type="button"
          id={"#{@id}-#{column_letter(col)}#{row + 1}"}
          data-col={col}
          data-row={row}
          phx-click={cell_clickable?(assigns, col, row) && @click_event}
          phx-value-coord={"#{column_letter(col)}#{row + 1}"}
          disabled={!cell_clickable?(assigns, col, row)}
          class={[
            "relative size-7 overflow-hidden border border-base-300/30 bg-sky-800 transition-colors",
            cell_clickable?(assigns, col, row) && "cursor-pointer hover:bg-sky-600",
            !cell_clickable?(assigns, col, row) && "cursor-default"
          ]}
        >
          <% segment = ship_segment(assigns, col, row) %>
          <.ship_segment :if={segment} segment={segment} />
          <.miss_marker :if={cell_shot(assigns, col, row) == "miss"} />
          <.hit_marker :if={cell_shot(assigns, col, row) in ["hit", "sunk"]} />
        </button>
      <% end %>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".PlacementPreview">
      export default {
        mounted() {
          this.el.addEventListener("mouseover", (e) => {
            const cell = e.target.closest("button[data-col]")
            if (cell) this.preview(cell)
          })

          this.el.addEventListener("mouseout", (e) => {
            const cell = e.target.closest("button[data-col]")
            if (cell) this.clearPreview()
          })
        },
        preview(originCell) {
          this.clearPreview()

          const length = parseInt(this.el.dataset.previewLength, 10)
          if (!length) return

          const horizontal = this.el.dataset.orientation === "horizontal"
          const col = parseInt(originCell.dataset.col, 10)
          const row = parseInt(originCell.dataset.row, 10)

          for (let i = 0; i < length; i++) {
            const c = horizontal ? col + i : col
            const r = horizontal ? row : row + i
            const cell = this.el.querySelector(`button[data-col="${c}"][data-row="${r}"]`)
            if (cell) cell.style.setProperty("background-color", "#f59e0b", "important")
          }
        },
        clearPreview() {
          this.el.querySelectorAll("button[data-col]").forEach((cell) => {
            cell.style.removeProperty("background-color")
          })
        }
      }
    </script>
    """
  end

  attr :segment, :map, required: true

  defp ship_segment(assigns) do
    ~H"""
    <svg
      viewBox="0 0 64 64"
      class={[
        "pointer-events-none absolute inset-0",
        !@segment.horizontal? && "rotate-90"
      ]}
    >
      <g :if={@segment.part == :bow}>
        <path
          d="M64,8 L24,8 C12,8 4,20 4,32 C4,44 12,56 24,56 L64,56 Z"
          fill={@segment.color}
        />
        <path d="M64,32 L16,32" stroke="#415a77" stroke-width="2" stroke-dasharray="6 4" />
        <circle cx="44" cy="20" r="2" fill="#e0e1dd" opacity="0.5" />
        <circle cx="44" cy="44" r="2" fill="#e0e1dd" opacity="0.5" />
      </g>

      <g :if={@segment.part == :hull}>
        <rect x="0" y="8" width="64" height="48" fill={@segment.color} />
        <line x1="0" y1="32" x2="64" y2="32" stroke="#415a77" stroke-width="2" stroke-dasharray="8 4" />
        <rect x="16" y="12" width="32" height="4" fill="#e0e1dd" opacity="0.3" />
        <rect x="16" y="48" width="32" height="4" fill="#e0e1dd" opacity="0.3" />
      </g>

      <g :if={@segment.part == :stern}>
        <path
          d="M0,8 L48,8 C56,8 60,16 60,32 C60,48 56,56 48,56 L0,56 Z"
          fill={@segment.color}
        />
        <line x1="0" y1="32" x2="48" y2="32" stroke="#415a77" stroke-width="2" stroke-dasharray="6 4" />
        <line x1="48" y1="16" x2="48" y2="48" stroke="#1b263b" stroke-width="3" />
      </g>
    </svg>
    """
  end

  defp hit_marker(assigns) do
    ~H"""
    <svg viewBox="0 0 64 64" class="pointer-events-none absolute inset-0">
      <circle cx="32" cy="32" r="8" fill="#e63946" />
      <line x1="32" y1="8" x2="32" y2="20" stroke="#e63946" stroke-width="3" stroke-linecap="round" />
      <line x1="32" y1="44" x2="32" y2="56" stroke="#e63946" stroke-width="3" stroke-linecap="round" />
      <line x1="8" y1="32" x2="20" y2="32" stroke="#e63946" stroke-width="3" stroke-linecap="round" />
      <line x1="44" y1="32" x2="56" y2="32" stroke="#e63946" stroke-width="3" stroke-linecap="round" />
    </svg>
    """
  end

  defp miss_marker(assigns) do
    ~H"""
    <svg viewBox="0 0 64 64" class="pointer-events-none absolute inset-0">
      <circle cx="32" cy="32" r="12" fill="none" stroke="#a8dadc" stroke-width="2.5" stroke-dasharray="4 2" />
      <circle cx="32" cy="32" r="3" fill="#a8dadc" />
    </svg>
    """
  end

  defp board_size, do: @board_size

  defp column_letter(col), do: Enum.at(@columns, col)

  defp cell_coord(col, row), do: column_letter(col) <> Integer.to_string(row + 1)

  defp cell_shot(assigns, col, row), do: Map.get(assigns.shots, cell_coord(col, row))

  # Returns `%{part: :bow | :hull | :stern, horizontal?: boolean, color: String.t()}`
  # for the ship occupying this cell (if any, and if it should be visible -
  # `reveal_only_sunk` hides anything but a fully-sunk ship), or `nil`.
  defp ship_segment(assigns, col, row) do
    coord = {col, row}

    ship =
      Enum.find(assigns.fleet, fn ship ->
        coord in ship.cells and (not assigns.reveal_only_sunk or ship_sunk?(ship))
      end)

    ship &&
      %{
        part: ship_part(Enum.find_index(ship.cells, &(&1 == coord)), length(ship.cells)),
        horizontal?: ship_horizontal?(ship),
        color: (ship_sunk?(ship) && @sunk_color) || @hull_color
      }
  end

  defp ship_part(0, _length), do: :bow
  defp ship_part(index, length) when index == length - 1, do: :stern
  defp ship_part(_index, _length), do: :hull

  defp ship_horizontal?(%{cells: [{_c0, row0}, {_c1, row1} | _]}), do: row0 == row1

  defp cell_clickable?(assigns, col, row),
    do: assigns.clickable and not assigns.disabled and is_nil(cell_shot(assigns, col, row))

  defp ship_sunk?(ship), do: MapSet.size(ship.hits) == length(ship.cells)
end
