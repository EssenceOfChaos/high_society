defmodule HighSociety.Games.Roulette do
  @moduledoc """
  Pure game logic for European (single-zero) Roulette: the wheel's pocket
  order and colors, drawing a winning number, and settling a set of bets
  against it, with no dependency on persistence or web.

  A bet is keyed by a short string identifying exactly what it covers -
  `"straight:17"`, `"red"`, `"dozen:2"`, `"column:3"`, etc. - mapped to its
  wagered amount in cents. That same key doubles as the id of the table
  cell it was placed on, so the LiveView can render placed chips without
  any separate lookup table.
  """

  @type key :: String.t()
  @type bets :: %{key() => pos_integer()}
  @type color :: :red | :black | :green
  @type settled_bet :: %{
          key: key(),
          amount: pos_integer(),
          payout: non_neg_integer(),
          won?: boolean()
        }

  # The physical order of pockets around a standard European wheel,
  # starting from 0 - used only to animate the wheel/ball to the winning
  # number's actual position, never to influence which number wins (that's
  # a plain uniform draw over 0..36).
  @wheel_order [
    0,
    32,
    15,
    19,
    4,
    21,
    2,
    25,
    17,
    34,
    6,
    27,
    13,
    36,
    11,
    30,
    8,
    23,
    10,
    5,
    24,
    16,
    33,
    1,
    20,
    14,
    31,
    9,
    22,
    18,
    29,
    7,
    28,
    12,
    35,
    3,
    26
  ]

  @red_numbers MapSet.new([
                 1,
                 3,
                 5,
                 7,
                 9,
                 12,
                 14,
                 16,
                 18,
                 19,
                 21,
                 23,
                 25,
                 27,
                 30,
                 32,
                 34,
                 36
               ])

  @max_bet 500 * 100

  @doc "The 37 pocket numbers in the order they actually sit around the wheel, starting from 0."
  @spec wheel_order() :: [0..36]
  def wheel_order, do: @wheel_order

  @doc "The maximum amount that may be wagered on any single spot, in cents."
  @spec max_bet() :: pos_integer()
  def max_bet, do: @max_bet

  @doc "The felt color a number is printed in - green for 0, else red or black."
  @spec color(0..36) :: color()
  def color(0), do: :green
  def color(n) when n in 1..36, do: if(n in @red_numbers, do: :red, else: :black)

  @doc "Draws a winning number, uniformly at random over 0..36."
  @spec spin() :: 0..36
  def spin, do: Enum.random(0..36)

  @doc """
  Whether `key` is a bet this module knows how to settle - straight bets on
  any number 0-36, or one of the fixed outside bets/dozens/columns.
  """
  @spec valid_key?(key()) :: boolean()
  def valid_key?(key), do: match?({:ok, _}, parse_key(key))

  @doc """
  Settles every bet in `bets` against `winning_number`, returning one
  `settled_bet` per entry with whether it won and what it pays (including
  the original stake - e.g. a winning straight bet pays 36x, not 35x).
  """
  @spec evaluate(0..36, bets()) :: [settled_bet()]
  def evaluate(winning_number, bets) do
    Enum.map(bets, fn {key, amount} ->
      {:ok, parsed} = parse_key(key)
      won? = covers?(parsed, winning_number)
      payout = if won?, do: amount * multiplier(parsed), else: 0

      %{key: key, amount: amount, payout: payout, won?: won?}
    end)
  end

  defp multiplier({:straight, _n}), do: 36
  defp multiplier(:red), do: 2
  defp multiplier(:black), do: 2
  defp multiplier(:odd), do: 2
  defp multiplier(:even), do: 2
  defp multiplier(:low), do: 2
  defp multiplier(:high), do: 2
  defp multiplier({:dozen, _d}), do: 3
  defp multiplier({:column, _c}), do: 3

  defp covers?({:straight, n}, winning_number), do: n == winning_number
  defp covers?(:red, winning_number), do: color(winning_number) == :red
  defp covers?(:black, winning_number), do: color(winning_number) == :black
  defp covers?(:odd, winning_number), do: winning_number != 0 and rem(winning_number, 2) == 1
  defp covers?(:even, winning_number), do: winning_number != 0 and rem(winning_number, 2) == 0
  defp covers?(:low, winning_number), do: winning_number in 1..18
  defp covers?(:high, winning_number), do: winning_number in 19..36

  defp covers?({:dozen, d}, winning_number) when winning_number in 1..36,
    do: div(winning_number - 1, 12) + 1 == d

  defp covers?({:dozen, _d}, 0), do: false

  defp covers?({:column, c}, winning_number) when winning_number in 1..36,
    do: rem(winning_number - 1, 3) + 1 == c

  defp covers?({:column, _c}, 0), do: false

  @spec parse_key(key()) :: {:ok, term()} | :error
  defp parse_key("straight:" <> n) do
    case Integer.parse(n) do
      {number, ""} when number in 0..36 -> {:ok, {:straight, number}}
      _ -> :error
    end
  end

  defp parse_key("dozen:" <> d) when d in ~w(1 2 3), do: {:ok, {:dozen, String.to_integer(d)}}
  defp parse_key("column:" <> c) when c in ~w(1 2 3), do: {:ok, {:column, String.to_integer(c)}}
  defp parse_key("red"), do: {:ok, :red}
  defp parse_key("black"), do: {:ok, :black}
  defp parse_key("odd"), do: {:ok, :odd}
  defp parse_key("even"), do: {:ok, :even}
  defp parse_key("low"), do: {:ok, :low}
  defp parse_key("high"), do: {:ok, :high}
  defp parse_key(_key), do: :error
end
