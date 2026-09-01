defmodule HighSociety.Games.BattleshipGame do
  @moduledoc """
  Persisted vs-computer Battleship game - one row per user, holding the
  full `HighSociety.Games.Battleship` match as jsonb (see
  `HighSociety.Games.Battleship.to_json/1`). `status` mirrors the match's
  own `status` field as a plain string so it can be queried directly
  (`get_active_battleship_game/1`) without decoding the jsonb payload.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          status: String.t(),
          wager: integer(),
          payout: integer() | nil,
          battleship: map(),
          user_id: integer() | nil
        }

  @statuses ~w(placing_fleets player_turn opponent_turn player_won opponent_won)

  schema "battleship_games" do
    field :status, :string, default: "placing_fleets"
    field :wager, :integer
    field :payout, :integer
    field :battleship, :map, default: %{}

    belongs_to :user, HighSociety.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(battleship_game, attrs) do
    battleship_game
    |> cast(attrs, [:status, :wager, :payout, :battleship, :user_id])
    |> validate_required([:status, :wager, :battleship, :user_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:wager, greater_than: 0)
  end
end
