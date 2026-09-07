defmodule HighSociety.Games.RouletteGame do
  @moduledoc """
  Persisted result of the user's latest Roulette spin. Like Slots, a spin
  always resolves fully server-side in one step, so there's one row per
  user, replaced on every spin - kept only so the last result is still
  shown on remount instead of an empty table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          winning_number: integer(),
          bets: [map()],
          total_wager: integer(),
          total_payout: integer(),
          user_id: integer() | nil
        }

  schema "roulette_games" do
    field :winning_number, :integer
    field :bets, {:array, :map}, default: []
    field :total_wager, :integer
    field :total_payout, :integer, default: 0

    belongs_to :user, HighSociety.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(roulette_game, attrs) do
    roulette_game
    |> cast(attrs, [:winning_number, :bets, :total_wager, :total_payout, :user_id])
    |> validate_required([:winning_number, :bets, :total_wager, :user_id])
    |> validate_number(:winning_number, greater_than_or_equal_to: 0, less_than_or_equal_to: 36)
    |> validate_number(:total_wager, greater_than: 0)
  end
end
