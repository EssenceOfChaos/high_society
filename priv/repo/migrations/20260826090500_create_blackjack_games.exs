defmodule HighSociety.Repo.Migrations.CreateBlackjackGames do
  use Ecto.Migration

  def change do
    create table(:blackjack_games) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "player_turn"
      add :shoe, {:array, :string}, null: false, default: []
      add :hands, {:array, :map}, null: false, default: []
      add :active_hand, :integer
      add :dealer_hand, {:array, :string}, null: false, default: []
      add :round_number, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:blackjack_games, [:user_id])
  end
end
