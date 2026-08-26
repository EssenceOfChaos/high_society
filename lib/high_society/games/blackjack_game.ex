defmodule HighSociety.Games.BlackjackGame do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(player_turn dealer_turn round_over)

  schema "blackjack_games" do
    field :status, :string, default: "player_turn"
    field :shoe, {:array, :string}, default: []
    field :hands, {:array, :map}, default: []
    field :active_hand, :integer
    field :dealer_hand, {:array, :string}, default: []
    field :round_number, :integer, default: 0

    belongs_to :user, HighSociety.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(blackjack_game, attrs) do
    blackjack_game
    |> cast(attrs, [
      :status,
      :shoe,
      :hands,
      :active_hand,
      :dealer_hand,
      :round_number,
      :user_id
    ])
    |> validate_required([:status, :shoe, :hands, :dealer_hand, :round_number, :user_id])
    |> validate_inclusion(:status, @statuses)
  end
end
