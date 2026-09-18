defmodule HighSociety.Games.TournamentBalancer do
  @moduledoc """
  Pure table-balancing logic for a running tournament: given every active
  table's current occupants, decides which players should move where so
  no table sits far emptier than another, and so the field consolidates
  onto a single table once it fits - the rule
  `HighSociety.Games.TournamentCoordinator` runs once after every
  elimination/seating batch (never once per player, so one bust-heavy hand
  doesn't thrash players through redundant moves). No process or IO here
  at all, so it's exercised directly by its own tests rather than through
  a live coordinator.
  """

  @type table :: %{slug: String.t(), user_ids: [pos_integer()]}
  @type move :: %{user_id: pos_integer(), from: String.t(), to: String.t()}

  @doc """
  The moves needed to keep `tables` balanced, given each table's seat
  `capacity`. Two rules, checked in this order:

    1. If every remaining player across every table would fit on one
       table, consolidate everyone onto whichever table already has the
       most players (fewest moves) and empty every other table - the
       rule that actually converges the field to a real final table
       (evening out alone never would: e.g. 4-and-3 across two tables has
       a gap of only 1 and would sit there forever under rule 2 alone).
    2. Otherwise, even out seat counts one player at a time - each move
       takes a player from the fullest table to the emptiest - until no
       table has more than one more player than any other.

  Returns `[]` (a no-op) for zero or one table, since there's nothing to
  balance against.
  """
  @spec rebalance([table()], pos_integer()) :: [move()]
  def rebalance(tables, _capacity) when length(tables) <= 1, do: []

  def rebalance(tables, capacity) do
    total = tables |> Enum.map(&length(&1.user_ids)) |> Enum.sum()

    if total <= capacity do
      consolidate(tables)
    else
      even_out(tables, capacity)
    end
  end

  defp consolidate(tables) do
    target = Enum.max_by(tables, &length(&1.user_ids))

    tables
    |> Enum.reject(&(&1.slug == target.slug))
    |> Enum.flat_map(fn table ->
      Enum.map(table.user_ids, &%{user_id: &1, from: table.slug, to: target.slug})
    end)
  end

  defp even_out(tables, capacity) do
    counts_by_slug = Map.new(tables, &{&1.slug, &1.user_ids})
    do_even_out(counts_by_slug, capacity, []) |> Enum.reverse()
  end

  defp do_even_out(counts_by_slug, capacity, moves) do
    {fullest_slug, fullest_ids} = Enum.max_by(counts_by_slug, fn {_slug, ids} -> length(ids) end)

    {emptiest_slug, emptiest_ids} =
      Enum.min_by(counts_by_slug, fn {_slug, ids} -> length(ids) end)

    cond do
      fullest_slug == emptiest_slug ->
        moves

      length(fullest_ids) - length(emptiest_ids) <= 1 ->
        moves

      length(emptiest_ids) >= capacity ->
        moves

      true ->
        [moving_user | rest] = fullest_ids
        move = %{user_id: moving_user, from: fullest_slug, to: emptiest_slug}

        counts_by_slug
        |> Map.put(fullest_slug, rest)
        |> Map.put(emptiest_slug, emptiest_ids ++ [moving_user])
        |> do_even_out(capacity, [move | moves])
    end
  end
end
