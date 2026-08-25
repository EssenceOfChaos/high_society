defmodule HighSociety.Games.WarGame do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(in_progress player_won computer_won)

  schema "war_games" do
    field :status, :string, default: "in_progress"
    field :player_deck, {:array, :string}, default: []
    field :computer_deck, {:array, :string}, default: []
    field :round_number, :integer, default: 0
    field :last_round, :map
    field :pending_war, :map

    belongs_to :user, HighSociety.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(war_game, attrs) do
    war_game
    |> cast(attrs, [
      :status,
      :player_deck,
      :computer_deck,
      :round_number,
      :last_round,
      :pending_war,
      :user_id
    ])
    |> validate_required([:status, :player_deck, :computer_deck, :round_number, :user_id])
    |> validate_inclusion(:status, @statuses)
  end
end
