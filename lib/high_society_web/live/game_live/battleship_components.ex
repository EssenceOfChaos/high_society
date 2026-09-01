defmodule HighSocietyWeb.GameLive.BattleshipComponents do
  @moduledoc """
  Shared Battleship board rendering, used by both the vs-computer
  (`HighSocietyWeb.GameLive.Battleship`) and live-match
  (`HighSocietyWeb.GameLive.BattleshipMatch`) screens - the same 10x10
  grid renders either a player's own fleet (every ship visible) or a
  tracking grid of shots fired at an opponent (`reveal_only_sunk: true`
  keeps anything but a fully-sunk ship hidden), with plain Tailwind
  cells rather than any image asset - there's no per-cell art needed.
  """
  use Phoenix.Component

  alias HighSociety.Games.Battleship

  @columns ~w(A B C D E F G H I J)
  @board_size Battleship.board_size()

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
      class="inline-grid gap-0.5"
      style={"grid-template-columns: 1.25rem repeat(#{board_size()}, 1.75rem);"}
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
            "size-7 rounded-sm border border-base-300/30 transition-colors",
            cell_class(assigns, col, row)
          ]}
        >
          <span
            :if={cell_shot(assigns, col, row) == "miss"}
            class="mx-auto block size-1.5 rounded-full bg-base-100/70"
          />
          <span
            :if={cell_shot(assigns, col, row) in ["hit", "sunk"]}
            class="block text-[10px] font-black text-base-100"
          >
            ×
          </span>
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

  defp board_size, do: @board_size

  defp column_letter(col), do: Enum.at(@columns, col)

  defp cell_coord(col, row), do: column_letter(col) <> Integer.to_string(row + 1)

  defp cell_shot(assigns, col, row), do: Map.get(assigns.shots, cell_coord(col, row))

  defp cell_ship?(assigns, col, row) do
    coord = {col, row}

    Enum.any?(assigns.fleet, fn ship ->
      coord in ship.cells and (not assigns.reveal_only_sunk or ship_sunk?(ship))
    end)
  end

  defp cell_clickable?(assigns, col, row),
    do: assigns.clickable and not assigns.disabled and is_nil(cell_shot(assigns, col, row))

  defp cell_class(assigns, col, row) do
    shot = cell_shot(assigns, col, row)
    clickable? = cell_clickable?(assigns, col, row)

    bg =
      cond do
        shot in ["hit", "sunk"] -> "bg-error"
        shot == "miss" -> "bg-sky-950"
        cell_ship?(assigns, col, row) -> "bg-slate-500"
        true -> "bg-sky-800"
      end

    [bg, (clickable? && "cursor-pointer hover:bg-sky-600") || "cursor-default"]
  end

  defp ship_sunk?(ship), do: MapSet.size(ship.hits) == length(ship.cells)
end
