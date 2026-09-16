defmodule HighSociety.Games.Slots do
  @moduledoc """
  Pure game logic for Slots: reel weighting, grid drawing, payline
  evaluation (with Wild substitution), and free-spin/multiplier bookkeeping,
  with no dependency on persistence or web.

  The grid is 6 columns x 4 rows (24 cells), stored as a flat, column-major
  list: cell `{col, row}` lives at `col * @rows + row`. A payline is a
  6-element list of row indices, one per column left-to-right; it's scored
  by walking its 6 symbols from the left and counting how far a run of
  identical symbols (Wild substituting for anything but Bonus) extends
  before it breaks, exactly like a real multi-line slot's left-to-right
  paylines.

  All payouts are expressed as integer "hundredths of the wager" (e.g. `30`
  means 0.30x the wager) rather than floats, so Token math downstream stays
  exact integer arithmetic (`HighSociety.Tokens`) with no floating point
  anywhere near it.
  """

  @rows 4
  @columns 6

  @type kind ::
          :cherries
          | :lemon
          | :grapes
          | :bell
          | :horseshoe
          | :crown
          | :star
          | :seven
          | :wild
          | :bonus
  @type grid :: [kind]
  @type payline :: [0..3]
  @type win :: %{
          payline: non_neg_integer(),
          kind: kind,
          length: 3..6,
          multiplier_hundredths: pos_integer()
        }

  @wager_options [25, 50, 75, 100, 125, 150, 175, 200, 250, 300, 500, 1000]

  # Identical reel strip on all 6 reels, weights sum to 200.
  @reel_weights [
    cherries: 41,
    lemon: 36,
    grapes: 32,
    bell: 28,
    horseshoe: 20,
    crown: 14,
    star: 10,
    seven: 6,
    wild: 8,
    bonus: 5
  ]
  @total_weight Enum.sum(Keyword.values(@reel_weights))

  # Row indices per column (left to right), one list per payline.
  @paylines [
    # horizontal
    [0, 0, 0, 0, 0, 0],
    [1, 1, 1, 1, 1, 1],
    [2, 2, 2, 2, 2, 2],
    [3, 3, 3, 3, 3, 3],
    # vertical (steep full-width alternations, distinct from the gentler zigzags below)
    [0, 3, 0, 3, 0, 3],
    [3, 0, 3, 0, 3, 0],
    [0, 2, 0, 2, 0, 2],
    [2, 0, 2, 0, 2, 0],
    [1, 3, 1, 3, 1, 3],
    [3, 1, 3, 1, 3, 1],
    # diagonal
    [0, 1, 1, 2, 2, 3],
    [3, 2, 2, 1, 1, 0],
    # zigzag
    [1, 2, 1, 2, 1, 2],
    [2, 1, 2, 1, 2, 1],
    [0, 1, 2, 3, 2, 1],
    [3, 2, 1, 0, 1, 2]
  ]

  @paytable %{
    cherries: %{3 => 30, 4 => 75, 5 => 200, 6 => 800},
    lemon: %{3 => 40, 4 => 100, 5 => 250, 6 => 1000},
    grapes: %{3 => 50, 4 => 125, 5 => 300, 6 => 1200},
    bell: %{3 => 60, 4 => 150, 5 => 400, 6 => 1500},
    horseshoe: %{3 => 100, 4 => 300, 5 => 800, 6 => 3000},
    crown: %{3 => 150, 4 => 400, 5 => 1200, 6 => 4500},
    star: %{3 => 200, 4 => 600, 5 => 2000, 6 => 7500},
    seven: %{3 => 300, 4 => 1000, 5 => 4000, 6 => 15000},
    wild: %{3 => 600, 4 => 2000, 5 => 8000, 6 => 30000}
  }

  @bonus_trigger_count 3
  @free_spins_award 9
  @free_spins_retrigger_award 5
  @free_spin_multiplier 3

  @doc "The 12 fixed wager amounts, in cents ($0.25 - $10.00)."
  @spec wager_options() :: [pos_integer()]
  def wager_options, do: @wager_options

  @doc "The number of Bonus symbols (anywhere on the grid) needed to trigger/retrigger free spins."
  @spec bonus_trigger_count() :: pos_integer()
  def bonus_trigger_count, do: @bonus_trigger_count

  @doc "Free spins awarded the first time a spin triggers the feature."
  @spec free_spins_award() :: pos_integer()
  def free_spins_award, do: @free_spins_award

  @doc "Extra free spins awarded when the feature retriggers during an active free-spins round."
  @spec free_spins_retrigger_award() :: pos_integer()
  def free_spins_retrigger_award, do: @free_spins_retrigger_award

  @doc "The flat multiplier applied to every win for the duration of a free-spins round."
  @spec free_spin_multiplier() :: pos_integer()
  def free_spin_multiplier, do: @free_spin_multiplier

  @doc "The per-reel symbol weights (identical on all reels), for RTP tuning/tests."
  @spec reel_weights() :: keyword(pos_integer())
  def reel_weights, do: @reel_weights

  @doc """
  The full symbol x run-length payout table (payouts in hundredths of the
  wager, same units as `win.multiplier_hundredths`), for display in the
  in-game paytable and for tests - sourced from the same data the payline
  evaluator itself reads, so a displayed payout can never drift from the
  actual one.
  """
  @spec paytable() :: %{kind() => %{(3..6) => pos_integer()}}
  def paytable, do: @paytable

  @doc "The board's column/row dimensions, `{columns, rows}`."
  @spec dimensions() :: {pos_integer(), pos_integer()}
  def dimensions, do: {@columns, @rows}

  @doc "The fixed set of paylines, each a list of #{@columns} row indices (one per column)."
  @spec paylines() :: [payline()]
  def paylines, do: @paylines

  @doc """
  Draws a fresh 24-cell grid and evaluates every payline against it (Wild
  substitution applied), scaling each win's payout by `feature_multiplier`
  (pass `free_spin_multiplier/0` during a free-spins round, `1` otherwise).
  """
  @spec spin(pos_integer()) :: %{
          grid: grid(),
          wins: [win()],
          total_multiplier_hundredths: non_neg_integer(),
          bonus_count: non_neg_integer()
        }
  def spin(feature_multiplier \\ 1), do: evaluate(draw_grid(), feature_multiplier)

  @doc """
  Evaluates a specific 24-cell `grid` against every payline (Wild
  substitution applied), scaling each win's payout by `feature_multiplier`.
  Split out from `spin/1` so payline/paytable/Wild-substitution logic can
  be tested against hand-built grids instead of only random ones.
  """
  @spec evaluate(grid(), pos_integer()) :: %{
          grid: grid(),
          wins: [win()],
          total_multiplier_hundredths: non_neg_integer(),
          bonus_count: non_neg_integer()
        }
  def evaluate(grid, feature_multiplier \\ 1)
      when is_integer(feature_multiplier) and feature_multiplier >= 1 do
    wins = evaluate_wins(grid, feature_multiplier)

    %{
      grid: grid,
      wins: wins,
      total_multiplier_hundredths: wins |> Enum.map(& &1.multiplier_hundredths) |> Enum.sum(),
      bonus_count: bonus_count(grid)
    }
  end

  @doc "How many Bonus symbols appear anywhere on `grid`."
  @spec bonus_count(grid()) :: non_neg_integer()
  def bonus_count(grid), do: Enum.count(grid, &(&1 == :bonus))

  @doc """
  Pure bookkeeping for the free-spins feature. `remaining` is the free-spin
  counter *after* this spin already consumed one (if it was itself a free
  spin - see `HighSociety.Games.spin/2`); `during_free_spin?` says whether
  the spin that just resolved was itself a free spin (distinguishing a
  fresh trigger, which resets the multiplier, from a retrigger, which
  doesn't); `multiplier` is the current feature multiplier; `bonus_count`
  is this spin's own Bonus-symbol count. Returns
  `{new_remaining, new_multiplier, triggered?}`.
  """
  @spec apply_bonus(non_neg_integer(), boolean(), pos_integer(), non_neg_integer()) ::
          {non_neg_integer(), pos_integer(), boolean()}
  def apply_bonus(remaining, during_free_spin?, multiplier, bonus_count) do
    cond do
      bonus_count < @bonus_trigger_count -> {remaining, multiplier, false}
      during_free_spin? -> {remaining + @free_spins_retrigger_award, multiplier, true}
      true -> {remaining + @free_spins_award, @free_spin_multiplier, true}
    end
  end

  defp draw_grid, do: for(_ <- 1..(@columns * @rows), do: draw_symbol())

  defp draw_symbol do
    draw_symbol(@reel_weights, :rand.uniform(@total_weight))
  end

  defp draw_symbol([{kind, weight} | rest], target) do
    if target <= weight, do: kind, else: draw_symbol(rest, target - weight)
  end

  defp evaluate_wins(grid, feature_multiplier) do
    @paylines
    |> Enum.with_index()
    |> Enum.flat_map(fn {payline, index} ->
      symbols = payline_symbols(grid, payline)
      {kind, length} = matched_run(symbols)

      case paytable_multiplier(kind, length) do
        nil ->
          []

        base_multiplier ->
          [
            %{
              payline: index,
              kind: kind,
              length: length,
              multiplier_hundredths: base_multiplier * feature_multiplier
            }
          ]
      end
    end)
  end

  defp payline_symbols(grid, payline) do
    payline
    |> Enum.with_index()
    |> Enum.map(fn {row, col} -> Enum.at(grid, col * @rows + row) end)
  end

  defp matched_run(symbols) do
    kind = Enum.find(symbols, &(&1 not in [:wild, :bonus])) || :wild
    {kind, count_matching(symbols, kind)}
  end

  defp count_matching(symbols, kind) do
    Enum.reduce_while(symbols, 0, fn
      :bonus, acc -> {:halt, acc}
      symbol, acc when symbol == kind or symbol == :wild -> {:cont, acc + 1}
      _symbol, acc -> {:halt, acc}
    end)
  end

  defp paytable_multiplier(_kind, length) when length < 3, do: nil
  defp paytable_multiplier(kind, length), do: @paytable |> Map.get(kind, %{}) |> Map.get(length)
end
