defmodule HighSociety.Repo.Migrations.CreateBaccaratGames do
  use Ecto.Migration

  def change do
    create table(:baccarat_games) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :player_hand, {:array, :string}, null: false, default: []
      add :banker_hand, {:array, :string}, null: false, default: []
      add :player_total, :integer, null: false
      add :banker_total, :integer, null: false
      add :outcome, :string, null: false
      add :bets, {:array, :map}, null: false, default: []
      add :total_wager, :integer, null: false
      add :total_payout, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:baccarat_games, [:user_id])
  end
end
