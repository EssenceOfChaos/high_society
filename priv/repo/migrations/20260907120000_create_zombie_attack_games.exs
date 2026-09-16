defmodule HighSociety.Repo.Migrations.CreateZombieAttackGames do
  use Ecto.Migration

  def change do
    create table(:zombie_attack_games) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "in_progress"
      add :wager, :integer, null: false
      add :payout, :integer
      add :wave_reached, :integer, null: false, default: 0
      add :wave_schedule, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:zombie_attack_games, [:user_id])
  end
end
