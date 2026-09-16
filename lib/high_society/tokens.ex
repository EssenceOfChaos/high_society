defmodule HighSociety.Tokens do
  @moduledoc """
  All Token amounts in the app (balances, wagers, bets, pots, stacks...)
  are integers - the same underlying integers that were once whole-dollar-
  then-cent amounts before the Tokens rebrand, now just relabeled with no
  further rescaling. `format/1` is the one place that turns a raw integer
  into a comma-grouped string for display; callers append the word
  "Tokens" themselves where the surrounding copy doesn't already make the
  unit clear.
  """

  @doc """
  Formats an integer Token amount as a comma-grouped string, e.g.
  `2_500_000` becomes `"2,500,000"` and `-150` becomes `"-150"`.

  ## Examples

      iex> HighSociety.Tokens.format(2_500_000)
      "2,500,000"

      iex> HighSociety.Tokens.format(0)
      "0"

      iex> HighSociety.Tokens.format(-150)
      "-150"

  """
  @spec format(integer()) :: String.t()
  def format(amount) when is_integer(amount) do
    sign = if amount < 0, do: "-", else: ""

    amount
    |> abs()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
    |> then(&"#{sign}#{&1}")
  end
end
