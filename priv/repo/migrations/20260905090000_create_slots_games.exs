defmodule HighSociety.Repo.Migrations.CreateSlotsGames do
  use Ecto.Migration

  def change do
    create table(:slots_games) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :grid, {:array, :string}, null: false, default: []
      add :wins, {:array, :map}, null: false, default: []
      add :wager, :integer, null: false
      add :total_win, :integer, null: false, default: 0
      add :free_spins_remaining, :integer, null: false, default: 0
      add :free_spin_multiplier, :integer, null: false, default: 1
      add :triggering_wager, :integer
      add :bonus_triggered, :boolean, null: false, default: false
      add :spins_taken, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:slots_games, [:user_id])
  end
end
