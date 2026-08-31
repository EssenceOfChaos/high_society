defmodule HighSociety.Games.Poker.HandEvaluator do
  @moduledoc """
  Pure 7-card hand evaluation: ranks the best 5-card poker hand achievable
  from any 7 cards (2 hole cards + 5 community cards), using the same
  card-string encoding as `HighSociety.Games.Blackjack` ("AS", "10H", "KD" -
  rank then suit; parsed via `HighSociety.Games.Blackjack.split_card/1`).

  A hand's rank is a comparable `{category, tiebreakers}` tuple - category 8
  (straight flush) down to 0 (high card), with `tiebreakers` a list of
  descending card values relevant to breaking ties within that category.
  Elixir's term ordering compares these tuples exactly the way poker hands
  should compare (higher category wins outright; within a category, the
  tiebreaker lists compare element by element), so the winner of a showdown
  is simply whoever holds the greatest rank, and equal ranks are a split
  pot.
  """

  alias HighSociety.Games.Blackjack

  @type card :: String.t()
  @type hand_rank :: {non_neg_integer(), [non_neg_integer()]}

  @doc "The best 5-card hand rank achievable from the given 7 cards."
  @spec rank([card]) :: hand_rank
  def rank(cards) when length(cards) == 7 do
    cards
    |> combinations(5)
    |> Enum.map(&rank_five/1)
    |> Enum.max()
  end

  @doc "The human-readable name of a hand rank's category, for a showdown callout."
  @spec category_name(hand_rank) :: String.t()
  def category_name({8, _}), do: "Straight Flush"
  def category_name({7, _}), do: "Four of a Kind"
  def category_name({6, _}), do: "Full House"
  def category_name({5, _}), do: "Flush"
  def category_name({4, _}), do: "Straight"
  def category_name({3, _}), do: "Three of a Kind"
  def category_name({2, _}), do: "Two Pair"
  def category_name({1, _}), do: "Pair"
  def category_name({0, _}), do: "High Card"

  defp rank_five(cards) do
    values = Enum.map(cards, &value/1) |> Enum.sort(:desc)
    suits = Enum.map(cards, fn card -> card |> Blackjack.split_card() |> elem(1) end)

    flush? = suits |> Enum.uniq() |> length() == 1
    {straight?, straight_high} = detect_straight(values)

    by_count =
      values
      |> Enum.frequencies()
      |> Enum.sort_by(fn {value, count} -> {-count, -value} end)
      |> Enum.map(fn {value, _count} -> value end)

    counts_pattern =
      values |> Enum.frequencies() |> Map.values() |> Enum.sort(:desc)

    cond do
      flush? and straight? -> {8, [straight_high]}
      counts_pattern == [4, 1] -> {7, by_count}
      counts_pattern == [3, 2] -> {6, by_count}
      flush? -> {5, values}
      straight? -> {4, [straight_high]}
      counts_pattern == [3, 1, 1] -> {3, by_count}
      counts_pattern == [2, 2, 1] -> {2, by_count}
      counts_pattern == [2, 1, 1, 1] -> {1, by_count}
      true -> {0, values}
    end
  end

  # A straight only exists when the 5 cards have 5 distinct values (any
  # duplicate value already rules a straight out) - either 5 consecutive
  # values, or the wheel (A-2-3-4-5, where the Ace counts low).
  defp detect_straight(values) do
    uniq = Enum.uniq(values)

    cond do
      length(uniq) != 5 -> {false, nil}
      uniq == [14, 5, 4, 3, 2] -> {true, 5}
      Enum.at(uniq, 0) - Enum.at(uniq, 4) == 4 -> {true, Enum.at(uniq, 0)}
      true -> {false, nil}
    end
  end

  defp value(card) do
    {rank, _suit} = Blackjack.split_card(card)
    rank_value(rank)
  end

  defp rank_value("A"), do: 14
  defp rank_value("K"), do: 13
  defp rank_value("Q"), do: 12
  defp rank_value("J"), do: 11
  defp rank_value(rank), do: String.to_integer(rank)

  defp combinations(_list, 0), do: [[]]
  defp combinations([], _k), do: []

  defp combinations([head | tail], k) do
    for(combo <- combinations(tail, k - 1), do: [head | combo]) ++ combinations(tail, k)
  end
end
