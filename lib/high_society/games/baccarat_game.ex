defmodule HighSociety.Games.BaccaratGame do
  @moduledoc """
  Persisted result of the user's latest Baccarat round. Like Slots and
  Roulette, a round always resolves fully server-side in one step (no
  player decisions once bets are placed), so there's one row per user,
  replaced on every round - kept only so the last result is still shown
  on remount instead of an empty table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          player_hand: [String.t()],
          banker_hand: [String.t()],
          player_total: integer(),
          banker_total: integer(),
          outcome: String.t(),
          bets: [map()],
          total_wager: integer(),
          total_payout: integer(),
          user_id: integer() | nil
        }

  schema "baccarat_games" do
    field :player_hand, {:array, :string}, default: []
    field :banker_hand, {:array, :string}, default: []
    field :player_total, :integer
    field :banker_total, :integer
    field :outcome, :string
    field :bets, {:array, :map}, default: []
    field :total_wager, :integer
    field :total_payout, :integer, default: 0

    belongs_to :user, HighSociety.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(baccarat_game, attrs) do
    baccarat_game
    |> cast(attrs, [
      :player_hand,
      :banker_hand,
      :player_total,
      :banker_total,
      :outcome,
      :bets,
      :total_wager,
      :total_payout,
      :user_id
    ])
    |> validate_required([
      :player_hand,
      :banker_hand,
      :player_total,
      :banker_total,
      :outcome,
      :total_wager,
      :user_id
    ])
    |> validate_inclusion(:outcome, ~w(player banker tie))
    |> validate_number(:total_wager, greater_than: 0)
  end
end
