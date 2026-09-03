defmodule HighSociety.Badges do
  @moduledoc """
  Badge catalog for player gamification. A player's badge is resolved from
  their `active_days_count` (see `HighSociety.Accounts.record_activity/1`) -
  the thresholds climb along the Fibonacci sequence so each rank takes
  meaningfully longer to reach than the last.
  """

  @badges [
    %{slug: "novice", name: "Novice", tagline: "Just getting started.", threshold: 0},
    %{slug: "apprentice", name: "Apprentice", tagline: "Learning the game.", threshold: 2},
    %{slug: "player", name: "Player", tagline: "Getting the hang of it.", threshold: 3},
    %{slug: "skilled", name: "Skilled", tagline: "Playing with purpose.", threshold: 5},
    %{slug: "expert", name: "Expert", tagline: "Consistent and confident.", threshold: 8},
    %{slug: "master", name: "Master", tagline: "Mastering the odds.", threshold: 13},
    %{
      slug: "grandmaster",
      name: "Grandmaster",
      tagline: "Precision and strategy.",
      threshold: 21
    },
    %{slug: "champion", name: "Champion", tagline: "Rising above the rest.", threshold: 34},
    %{slug: "legend", name: "Legend", tagline: "A true force at the table.", threshold: 55},
    %{slug: "high-society", name: "High Society", tagline: "Among the elite.", threshold: 89}
  ]

  @type badge :: %{
          slug: String.t(),
          name: String.t(),
          tagline: String.t(),
          threshold: non_neg_integer()
        }

  @doc "The full badge catalog, ordered from lowest to highest rank."
  @spec all() :: [badge()]
  def all, do: @badges

  @doc """
  Returns the highest badge a player with `active_days_count` active days
  has earned.

  ## Examples

      iex> for_active_days(0)
      %{slug: "novice", name: "Novice", ...}

      iex> for_active_days(21)
      %{slug: "grandmaster", name: "Grandmaster", ...}

  """
  @spec for_active_days(non_neg_integer()) :: badge()
  def for_active_days(active_days_count) when is_integer(active_days_count) do
    @badges
    |> Enum.reverse()
    |> Enum.find(&(active_days_count >= &1.threshold))
  end
end
