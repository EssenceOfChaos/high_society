defmodule HighSociety.Games.PokerTables do
  @moduledoc """
  The fixed set of Poker cash-game tables. Unlike a hand's state, this
  configuration isn't user-created or persisted - it's compile-time data,
  same in spirit as `HighSocietyWeb.DashboardLive`'s `@games` list. Buy-in
  bounds are derived from the blinds rather than stored, so a table's
  stakes and its buy-in range can never drift apart.
  """

  @tables [
    %{slug: "new-york", name: "New York", small_blind: 1, big_blind: 2},
    %{slug: "paris", name: "Paris", small_blind: 2, big_blind: 4},
    %{slug: "london", name: "London", small_blind: 5, big_blind: 10}
  ]

  @seats 8
  @min_buy_in_multiplier 20
  @max_buy_in_multiplier 100

  @type table :: %{
          slug: String.t(),
          name: String.t(),
          small_blind: pos_integer(),
          big_blind: pos_integer()
        }

  @doc "Every configured table."
  @spec all() :: [table]
  def all, do: @tables

  @doc "The table config for `slug`, or `nil` if it doesn't exist."
  @spec get(String.t()) :: table | nil
  def get(slug), do: Enum.find(@tables, &(&1.slug == slug))

  @doc "How many seats a table has."
  @spec seats() :: pos_integer()
  def seats, do: @seats

  @doc "The minimum buy-in for a table (20x its big blind)."
  @spec min_buy_in(table) :: pos_integer()
  def min_buy_in(%{big_blind: big_blind}), do: big_blind * @min_buy_in_multiplier

  @doc "The maximum buy-in for a table (100x its big blind)."
  @spec max_buy_in(table) :: pos_integer()
  def max_buy_in(%{big_blind: big_blind}), do: big_blind * @max_buy_in_multiplier
end
