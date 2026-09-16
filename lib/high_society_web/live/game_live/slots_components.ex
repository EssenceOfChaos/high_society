defmodule HighSocietyWeb.GameLive.SlotsComponents do
  @moduledoc """
  Shared Slots rendering: the neon-outline symbol glyphs and the 6x4 reel
  grid. Like `HighSocietyWeb.GameLive.BattleshipComponents`, every symbol is
  a small hand-drawn inline SVG - no external image asset.
  """
  use Phoenix.Component

  import HighSocietyWeb.CoreComponents, only: [icon: 1]

  alias HighSociety.Games.Slots

  @kinds ~w(cherries lemon grapes bell horseshoe crown star seven wild bonus)a

  # Paytable row order, low to high value - matches @reel_weights' rarity
  # ordering in `HighSociety.Games.Slots`. Bonus has its own explanation
  # below the table since it doesn't pay out on a payline.
  @paytable_kinds ~w(cherries lemon grapes bell horseshoe crown star seven wild)a

  attr :kind, :atom, required: true
  attr :class, :string, default: ""

  @doc "One neon-outline symbol glyph, colored and shaped by `kind`."
  def symbol(assigns) do
    ~H"""
    <svg
      viewBox="0 0 64 64"
      fill="none"
      stroke="currentColor"
      stroke-width="3"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={[symbol_color(@kind), "drop-shadow-[0_0_6px_currentColor]", @class]}
    >
      <g :if={@kind == :cherries}>
        <circle cx="22" cy="46" r="10" />
        <circle cx="42" cy="46" r="10" />
        <path d="M22,37 C22,22 30,14 34,9" />
        <path d="M42,37 C42,26 36,17 34,9" />
        <path d="M34,9 C38,5 44,6 46,10 C42,11 37,12 34,9 Z" />
      </g>

      <g :if={@kind == :lemon}>
        <path d="M8,32 C8,19 18,9 32,9 C46,9 56,19 56,32 C56,45 46,55 32,55 C18,55 8,45 8,32 Z" />
        <path d="M31,9 C34,4 41,4 44,8 C40,10 35,12 31,9 Z" />
      </g>

      <g :if={@kind == :grapes}>
        <circle cx="24" cy="20" r="6" />
        <circle cx="40" cy="20" r="6" />
        <circle cx="16" cy="32" r="6" />
        <circle cx="32" cy="32" r="6" />
        <circle cx="48" cy="32" r="6" />
        <circle cx="24" cy="44" r="6" />
        <circle cx="40" cy="44" r="6" />
        <path d="M32,14 C32,8 38,5 42,7" />
      </g>

      <g :if={@kind == :bell}>
        <circle cx="32" cy="8" r="3" />
        <path d="M32,12 C22,12 20,22 20,29 C20,37 16,41 16,45 L48,45 C48,41 44,37 44,29 C44,22 42,12 32,12 Z" />
        <line x1="24" y1="49" x2="40" y2="49" />
        <circle cx="32" cy="53" r="3" />
      </g>

      <g :if={@kind == :horseshoe}>
        <path d="M18,52 L18,28 A14,14 0 0 1 46,28 L46,52" stroke-width="7" />
        <circle cx="18" cy="40" r="1.5" fill="currentColor" />
        <circle cx="46" cy="40" r="1.5" fill="currentColor" />
      </g>

      <g :if={@kind == :crown}>
        <path d="M12,44 L12,24 L22,34 L32,17 L42,34 L52,24 L52,44 Z" />
        <line x1="12" y1="44" x2="52" y2="44" />
        <circle cx="12" cy="24" r="2.5" fill="currentColor" />
        <circle cx="32" cy="17" r="2.5" fill="currentColor" />
        <circle cx="52" cy="24" r="2.5" fill="currentColor" />
      </g>

      <g :if={@kind == :star}>
        <path d="M32,6 L38,24 L58,24 L42,36 L48,54 L32,42 L16,54 L22,36 L6,24 L26,24 Z" />
      </g>

      <g :if={@kind == :seven}>
        <path d="M15,12 L49,12 L27,55" />
      </g>

      <g :if={@kind == :wild}>
        <path d="M16,26 L32,9 L48,26 L32,58 Z" />
        <line x1="16" y1="26" x2="48" y2="26" />
        <line x1="24" y1="26" x2="32" y2="58" />
        <line x1="40" y1="26" x2="32" y2="58" />
      </g>

      <g :if={@kind == :bonus}>
        <rect x="14" y="26" width="36" height="28" rx="2" />
        <line x1="32" y1="26" x2="32" y2="54" />
        <line x1="14" y1="38" x2="50" y2="38" />
        <circle cx="26" cy="20" r="6" />
        <circle cx="38" cy="20" r="6" />
      </g>
    </svg>
    """
  end

  defp symbol_color(:cherries), do: "text-rose-400"
  defp symbol_color(:lemon), do: "text-yellow-300"
  defp symbol_color(:grapes), do: "text-violet-400"
  defp symbol_color(:bell), do: "text-amber-300"
  defp symbol_color(:horseshoe), do: "text-orange-400"
  defp symbol_color(:crown), do: "text-yellow-500"
  defp symbol_color(:star), do: "text-cyan-300"
  defp symbol_color(:seven), do: "text-red-400"
  defp symbol_color(:wild), do: "text-fuchsia-400"
  defp symbol_color(:bonus), do: "text-emerald-400"

  attr :bonus?, :boolean, default: false
  slot :inner_block, required: true

  @doc """
  The decorative cabinet frame around the reel grid - a dark, neon-trimmed
  panel with a twinkling marquee-light strip top and bottom, so the reels
  read as a slot machine rather than a bare grid floating on the page.
  While `bonus?` (an active free-spins round), the trim and lights switch
  from amber to emerald and glow harder, so the whole cabinet visibly
  signals that something special is happening beyond just the on-grid text.
  """
  def cabinet(assigns) do
    ~H"""
    <div class={[
      "rounded-[2rem] bg-gradient-to-b from-neutral-800 via-neutral-900 to-black p-3 shadow-2xl ring-2 transition-colors duration-500 sm:p-5",
      if(@bonus?,
        do: "ring-emerald-400/70 shadow-[0_0_45px_-5px_rgba(52,211,153,0.6)]",
        else: "ring-amber-400/40"
      )
    ]}>
      <div class="flex justify-center gap-2 pb-3 sm:gap-3 sm:pb-4">
        <span
          :for={i <- 0..12}
          class={[
            "size-1.5 rounded-full sm:size-2",
            marquee_light_color_class(@bonus?),
            marquee_light_class(i)
          ]}
        />
      </div>

      {render_slot(@inner_block)}

      <div class="flex justify-center gap-2 pt-3 sm:gap-3 sm:pt-4">
        <span
          :for={i <- 0..12}
          class={[
            "size-1.5 rounded-full sm:size-2",
            marquee_light_color_class(@bonus?),
            marquee_light_class(i)
          ]}
        />
      </div>
    </div>
    """
  end

  defp marquee_light_color_class(true),
    do: "bg-emerald-300 shadow-[0_0_8px_3px_rgba(52,211,153,0.8)]"

  defp marquee_light_color_class(false),
    do: "bg-amber-300 shadow-[0_0_6px_2px_rgba(252,211,77,0.7)]"

  defp marquee_light_class(i) when rem(i, 3) == 0, do: "animate-pulse [animation-delay:0ms]"
  defp marquee_light_class(i) when rem(i, 3) == 1, do: "animate-pulse [animation-delay:200ms]"
  defp marquee_light_class(_i), do: "animate-pulse [animation-delay:400ms]"

  attr :show, :boolean, default: false

  @doc """
  A "how to win" reference sheet: the full symbol x run-length paytable
  plus the Bonus-symbol trigger/retrigger rules. Every number is read
  from `HighSociety.Games.Slots` (not hand-copied) so the copy can never
  drift from the actual payout/bonus logic. Toggled by a `phx-click`
  event the parent LiveView owns, same as `join_modal` in
  `HighSocietyWeb.GameLive.PokerTable`.
  """
  def paytable_modal(assigns) do
    assigns =
      assigns
      |> assign(:paytable, Slots.paytable())
      |> assign(:paytable_kinds, @paytable_kinds)
      |> assign(:bonus_trigger_count, Slots.bonus_trigger_count())
      |> assign(:free_spins_award, Slots.free_spins_award())
      |> assign(:free_spins_retrigger_award, Slots.free_spins_retrigger_award())
      |> assign(:free_spin_multiplier, Slots.free_spin_multiplier())

    ~H"""
    <div
      :if={@show}
      id="paytable-modal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    >
      <div
        phx-click-away="close_paytable"
        class="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-2xl bg-base-100 p-6 shadow-xl"
      >
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-bold">Paytable & Bonus Round</h2>
          <button
            type="button"
            phx-click="close_paytable"
            class="btn btn-ghost btn-sm btn-circle"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <p class="mt-2 text-sm text-base-content/60">
          Match 3 or more identical symbols left-to-right, starting at the leftmost reel, on any
          of the {length(Slots.paylines())} paylines. A
          <span class="font-semibold text-fuchsia-400">Wild</span>
          substitutes for any symbol except <span class="font-semibold text-emerald-400">Bonus</span>. Payouts are multiples of your wager, and every payline that hits pays out on the same spin.
        </p>

        <table class="mt-4 w-full text-sm">
          <thead>
            <tr class="text-left text-xs uppercase tracking-wide text-base-content/50">
              <th class="py-1">Symbol</th>
              <th class="py-1 text-right">3x</th>
              <th class="py-1 text-right">4x</th>
              <th class="py-1 text-right">5x</th>
              <th class="py-1 text-right">6x</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={kind <- @paytable_kinds} class="border-t border-base-content/10">
              <td class="flex items-center gap-2 py-2">
                <.symbol kind={kind} class="size-6" />
                <span class="capitalize">{kind}</span>
              </td>
              <td :for={length <- 3..6} class="text-right font-mono">
                {payout_label(@paytable, kind, length)}
              </td>
            </tr>
          </tbody>
        </table>

        <div class="mt-4 rounded-lg bg-emerald-400/10 p-3 text-sm">
          <p class="flex items-center gap-2 font-semibold text-emerald-400">
            <.symbol kind={:bonus} class="size-5" /> Bonus Round
          </p>
          <p class="mt-1 text-base-content/70">
            Land {@bonus_trigger_count} or more Bonus symbols anywhere on the grid (paylines don't
            matter) to trigger <strong>{@free_spins_award} free spins</strong>
            at a <strong>{@free_spin_multiplier}x</strong>
            payout multiplier. Landing {@bonus_trigger_count}+ Bonus symbols again during an
            active free-spins round retriggers the feature, adding
            <strong>{@free_spins_retrigger_award} more spins</strong>
            at the same multiplier.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp payout_label(paytable, kind, length) do
    case paytable |> Map.fetch!(kind) |> Map.get(length) do
      nil -> "—"
      hundredths -> "#{:erlang.float_to_binary(hundredths / 100, decimals: 2)}x"
    end
  end

  attr :grid, :list, default: nil
  attr :wins, :list, default: []
  attr :spinning?, :boolean, default: false
  attr :bonus_triggered?, :boolean, default: false

  @doc """
  The 6x4 reel grid. Given `grid` (24 symbol-name strings, column-major)
  and `wins` (this spin's persisted wins), highlights every cell that's
  part of a winning payline's matched run. While `spinning?`, each column
  instead shows a looping decorative strip - the real result is already
  decided server-side (see `HighSocietyWeb.GameLive.Slots`) and simply
  isn't shown yet. When `bonus_triggered?`, every Bonus symbol on the grid
  gets its own emerald highlight (distinct from the amber payline
  highlight) so it's visually obvious which symbols earned the bonus.
  """
  def grid(assigns) do
    assigns =
      assigns
      |> assign(:highlighted, highlighted_cells(assigns.grid, assigns.wins))
      |> assign(:bonus_cells, bonus_cells(assigns.grid, assigns.bonus_triggered?))

    ~H"""
    <div id="slots-grid" class="grid grid-cols-6 gap-2 rounded-box bg-black/40 p-4 sm:gap-3 sm:p-6">
      <div :for={col <- 0..5} class="h-[248px] overflow-hidden sm:h-[356px]">
        <div
          :if={@spinning?}
          class={["reel-spin-strip flex flex-col gap-2 sm:gap-3", reel_speed_class(col)]}
        >
          <div
            :for={kind <- spin_filler(col)}
            class="flex size-14 items-center justify-center rounded-lg bg-white/10 p-2 sm:size-20"
          >
            <.symbol kind={kind} class="size-full opacity-60" />
          </div>
        </div>

        <div :if={!@spinning?} class="flex flex-col gap-2 sm:gap-3">
          <div
            :for={row <- 0..3}
            id={"slots-cell-#{col}-#{row}"}
            class={[
              "card-deal-in flex size-14 items-center justify-center rounded-lg p-2 transition-colors sm:size-20",
              cell_highlight_class({col, row}, @bonus_cells, @highlighted)
            ]}
          >
            <.symbol :if={@grid} kind={cell_kind(@grid, col, row)} class="size-full" />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp cell_kind(grid, col, row), do: grid |> Enum.at(col * 4 + row) |> String.to_existing_atom()

  defp cell_highlight_class(cell, bonus_cells, highlighted) do
    cond do
      cell in bonus_cells -> "bg-emerald-400/25 ring-2 ring-emerald-300 animate-pulse"
      cell in highlighted -> "bg-amber-400/20 ring-2 ring-amber-300"
      true -> "bg-white/10"
    end
  end

  defp highlighted_cells(nil, _wins), do: MapSet.new()

  defp highlighted_cells(_grid, wins) do
    Enum.reduce(wins, MapSet.new(), fn win, acc ->
      payline = Enum.at(Slots.paylines(), win["payline"])

      payline
      |> Enum.take(win["length"])
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {row, col}, acc -> MapSet.put(acc, {col, row}) end)
    end)
  end

  defp bonus_cells(_grid, false), do: MapSet.new()
  defp bonus_cells(nil, true), do: MapSet.new()

  defp bonus_cells(grid, true) do
    for col <- 0..5, row <- 0..3, cell_kind(grid, col, row) == :bonus, into: MapSet.new() do
      {col, row}
    end
  end

  # A short, fixed decorative cycle - shown only while spinning, so it
  # never needs to be the true (already-decided) result. Repeated back to
  # back (20 items, not 10) so the CSS `reel-spin` loop above, which
  # translates by exactly half the strip's height, always lands back on
  # an identical copy of the same symbols rather than jumping mid-cycle.
  defp spin_filler(col) do
    rotated =
      @kinds
      |> Enum.drop(rem(col, length(@kinds)))
      |> Kernel.++(@kinds)
      |> Enum.take(length(@kinds))

    rotated ++ rotated
  end

  defp reel_speed_class(0), do: "[animation-duration:0.35s]"
  defp reel_speed_class(1), do: "[animation-duration:0.4s]"
  defp reel_speed_class(2), do: "[animation-duration:0.45s]"
  defp reel_speed_class(3), do: "[animation-duration:0.5s]"
  defp reel_speed_class(4), do: "[animation-duration:0.55s]"
  defp reel_speed_class(5), do: "[animation-duration:0.6s]"
end
