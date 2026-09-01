defmodule HighSociety.Games.BattleshipAI do
  @moduledoc """
  Picks the computer opponent's next shot with a classic hunt/target
  strategy. Pure and stateless: everything it needs - which cells have
  already been shot, and which hits already belong to a fully-sunk ship
  - is recomputed fresh from the caller's current board state on every
  call, so there's no separate AI "memory" that would need to be
  persisted and round-tripped through jsonb alongside the game itself.
  """

  alias HighSociety.Games.Battleship

  @type coord :: Battleship.coord()

  @doc """
  Chooses the next cell to fire at, given the cells already shot
  (`shots_fired`, hit or miss) and the cells belonging to ships that are
  already fully sunk (`sunk_ship_cells` - so a hit on one of them is no
  longer "live" and worth chasing).

  Hunts on a checkerboard parity pattern while no live hit is pending -
  since the smallest ship is length 2, this is guaranteed to eventually
  touch every possible ship placement while roughly halving the search
  space. Once a live hit exists, targets its orthogonal neighbors; once
  two live hits align, extends along that line (filling any gap between
  them left by parity hunting, and reaching past either end) until it
  runs off the board or into a recorded miss, at which point that
  direction simply stops being a candidate - no explicit bookkeeping is
  needed since candidates are always recomputed from the current shots.
  """
  @spec choose_shot(%{coord => :hit | :miss}, [coord], pos_integer) :: coord
  def choose_shot(shots_fired, sunk_ship_cells, board_size \\ Battleship.board_size()) do
    live_hits =
      shots_fired
      |> Enum.filter(fn {_coord, result} -> result == :hit end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&(&1 in sunk_ship_cells))

    case target_candidates(live_hits, shots_fired, board_size) do
      [] -> hunt(shots_fired, board_size)
      candidates -> Enum.random(candidates)
    end
  end

  defp target_candidates([], _shots_fired, _board_size), do: []

  defp target_candidates([single], shots_fired, board_size),
    do: neighbor_candidates([single], shots_fired, board_size)

  defp target_candidates(live_hits, shots_fired, board_size) do
    cols = live_hits |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    rows = live_hits |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    cond do
      length(rows) == 1 -> line_candidates(live_hits, :horizontal, shots_fired, board_size)
      length(cols) == 1 -> line_candidates(live_hits, :vertical, shots_fired, board_size)
      true -> neighbor_candidates(live_hits, shots_fired, board_size)
    end
  end

  defp line_candidates(live_hits, :horizontal, shots_fired, board_size) do
    [{_col, row} | _] = live_hits
    cols = Enum.map(live_hits, &elem(&1, 0))
    (Enum.min(cols) - 1)..(Enum.max(cols) + 1)
    |> Enum.map(&{&1, row})
    |> untried(shots_fired, board_size)
  end

  defp line_candidates(live_hits, :vertical, shots_fired, board_size) do
    [{col, _row} | _] = live_hits
    rows = Enum.map(live_hits, &elem(&1, 1))
    (Enum.min(rows) - 1)..(Enum.max(rows) + 1)
    |> Enum.map(&{col, &1})
    |> untried(shots_fired, board_size)
  end

  defp neighbor_candidates(hits, shots_fired, board_size) do
    hits
    |> Enum.flat_map(&orthogonal_neighbors/1)
    |> Enum.uniq()
    |> untried(shots_fired, board_size)
  end

  defp orthogonal_neighbors({col, row}),
    do: [{col + 1, row}, {col - 1, row}, {col, row + 1}, {col, row - 1}]

  defp hunt(shots_fired, board_size) do
    parity_cells =
      for col <- 0..(board_size - 1),
          row <- 0..(board_size - 1),
          rem(col + row, 2) == 0,
          not Map.has_key?(shots_fired, {col, row}),
          do: {col, row}

    case parity_cells do
      [] ->
        all_untried =
          for col <- 0..(board_size - 1),
              row <- 0..(board_size - 1),
              not Map.has_key?(shots_fired, {col, row}),
              do: {col, row}

        Enum.random(all_untried)

      cells ->
        Enum.random(cells)
    end
  end

  defp untried(coords, shots_fired, board_size) do
    Enum.filter(coords, fn {col, row} = coord ->
      col in 0..(board_size - 1) and row in 0..(board_size - 1) and
        not Map.has_key?(shots_fired, coord)
    end)
  end
end
