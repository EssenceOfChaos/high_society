defmodule HighSociety.Games.BlackjackGame do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          status: String.t(),
          shoe: [String.t()],
          hands: [
            %{
              cards: [String.t()],
              bet: integer(),
              status: String.t(),
              outcome: String.t() | nil,
              payout: integer() | nil
            }
          ],
          active_hand: integer() | nil,
          dealer_hand: [String.t()],
          round_number: integer(),
          user_id: integer() | nil
        }

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
