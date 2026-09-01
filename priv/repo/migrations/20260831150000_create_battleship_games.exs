defmodule HighSociety.Repo.Migrations.CreateBattleshipGames do
  use Ecto.Migration

  def change do
    create table(:battleship_games) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "placing_fleets"
      add :wager, :integer, null: false
      add :payout, :integer
      add :battleship, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:battleship_games, [:user_id])
  end
end
