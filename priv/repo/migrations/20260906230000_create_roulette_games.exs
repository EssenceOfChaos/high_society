defmodule HighSociety.Repo.Migrations.CreateRouletteGames do
  use Ecto.Migration

  def change do
    create table(:roulette_games) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :winning_number, :integer, null: false
      add :bets, {:array, :map}, null: false, default: []
      add :total_wager, :integer, null: false
      add :total_payout, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:roulette_games, [:user_id])
  end
end
