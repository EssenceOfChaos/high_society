defmodule HighSociety.Games.TournamentBalancerTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.TournamentBalancer

  describe "rebalance/2" do
    test "no-op for zero or one table" do
      assert TournamentBalancer.rebalance([], 8) == []
      assert TournamentBalancer.rebalance([%{slug: "a", user_ids: [1, 2]}], 8) == []
    end

    test "no-op when already balanced (gap of 1)" do
      tables = [
        %{slug: "a", user_ids: [1, 2, 3, 4]},
        %{slug: "b", user_ids: [5, 6, 7]}
      ]

      # capacity 4 keeps the total (7) too big to consolidate onto one table
      assert TournamentBalancer.rebalance(tables, 4) == []
    end

    test "evens out a gap greater than 1 by moving from the fullest to the emptiest table" do
      tables = [
        %{slug: "a", user_ids: [1, 2, 3, 4, 5]},
        %{slug: "b", user_ids: [6]}
      ]

      # capacity 5 keeps the total (6) too big to consolidate onto one table
      moves = TournamentBalancer.rebalance(tables, 5)

      assert moves == [
               %{user_id: 1, from: "a", to: "b"},
               %{user_id: 2, from: "a", to: "b"}
             ]

      final = apply_moves(tables, moves)
      counts = Enum.map(final, &length(&1.user_ids))
      assert counts == [3, 3]
    end

    test "keeps evening out (one move at a time) until the gap is 1 or less" do
      tables = [
        %{slug: "a", user_ids: [1, 2, 3, 4, 5, 6]},
        %{slug: "b", user_ids: []}
      ]

      moves = TournamentBalancer.rebalance(tables, 4)

      assert moves == [
               %{user_id: 1, from: "a", to: "b"},
               %{user_id: 2, from: "a", to: "b"},
               %{user_id: 3, from: "a", to: "b"}
             ]

      final = apply_moves(tables, moves)
      counts = Enum.map(final, &length(&1.user_ids))
      assert counts == [3, 3]
    end

    test "refuses to move anyone once the only less-full table is already at capacity" do
      tables = [
        %{slug: "a", user_ids: [1, 2, 3, 4, 5]},
        %{slug: "b", user_ids: [6, 7, 8]}
      ]

      # capacity 3: "b" is already full even though the gap (5 vs 3) is 2
      assert TournamentBalancer.rebalance(tables, 3) == []
    end

    test "consolidates onto the fullest table once everyone fits on one table" do
      tables = [
        %{slug: "a", user_ids: [1, 2, 3, 4]},
        %{slug: "b", user_ids: [5, 6, 7]}
      ]

      moves = TournamentBalancer.rebalance(tables, 8)

      assert Enum.sort(moves) ==
               Enum.sort([
                 %{user_id: 5, from: "b", to: "a"},
                 %{user_id: 6, from: "b", to: "a"},
                 %{user_id: 7, from: "b", to: "a"}
               ])
    end

    test "consolidates three tables down to one when the total fits" do
      tables = [
        %{slug: "a", user_ids: [1, 2]},
        %{slug: "b", user_ids: [3, 4, 5]},
        %{slug: "c", user_ids: [6]}
      ]

      moves = TournamentBalancer.rebalance(tables, 8)
      targets = moves |> Enum.map(& &1.to) |> Enum.uniq()

      assert targets == ["b"]
      assert Enum.map(moves, & &1.user_id) |> Enum.sort() == [1, 2, 6]
    end

    test "the exact boundary - total equals capacity still consolidates" do
      tables = [
        %{slug: "a", user_ids: [1, 2, 3, 4]},
        %{slug: "b", user_ids: [5, 6, 7, 8]}
      ]

      moves = TournamentBalancer.rebalance(tables, 8)
      assert length(moves) == 4
    end
  end

  describe "convergence" do
    test "applying the returned moves always leaves every table within a gap of 1, respecting capacity" do
      tables = [
        %{slug: "a", user_ids: Enum.to_list(1..7)},
        %{slug: "b", user_ids: []}
      ]

      moves = TournamentBalancer.rebalance(tables, 4)
      final = apply_moves(tables, moves)

      counts = Enum.map(final, &length(&1.user_ids))
      assert Enum.max(counts) - Enum.min(counts) <= 1
      assert Enum.all?(counts, &(&1 <= 4))
    end
  end

  defp apply_moves(tables, moves) do
    Enum.reduce(moves, tables, fn move, tables ->
      Enum.map(tables, fn
        %{slug: slug} = table when slug == move.from ->
          %{table | user_ids: List.delete(table.user_ids, move.user_id)}

        %{slug: slug} = table when slug == move.to ->
          %{table | user_ids: [move.user_id | table.user_ids]}

        table ->
          table
      end)
    end)
  end
end
