defmodule HighSociety.Money do
  @moduledoc """
  All money in the app (balances, wagers, bets, pots, stacks...) is stored
  and computed as an integer number of cents, so arithmetic never has to
  deal with floating-point rounding. `format/1` is the one place that turns
  cents back into a comma-grouped dollar-and-cents string for display.
  """

  @doc """
  Formats an integer cent amount as a comma-grouped decimal string, e.g.
  `2_500_000` becomes `"25,000.00"` and `-150` becomes `"-1.50"`. Callers
  supply their own `$` prefix.

  ## Examples

      iex> HighSociety.Money.format(2_500_000)
      "25,000.00"

      iex> HighSociety.Money.format(0)
      "0.00"

      iex> HighSociety.Money.format(-150)
      "-1.50"

  """
  @spec format(integer()) :: String.t()
  def format(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)

    dollars =
      cents
      |> div(100)
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    remainder = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{sign}#{dollars}.#{remainder}"
  end
end
