defmodule HighSociety.Repo.Migrations.CreateWarGames do
  use Ecto.Migration

  def change do
    create table(:war_games) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "in_progress"
      add :player_deck, {:array, :string}, null: false, default: []
      add :computer_deck, {:array, :string}, null: false, default: []
      add :round_number, :integer, null: false, default: 0
      add :last_round, :map

      timestamps(type: :utc_datetime)
    end

    create index(:war_games, [:user_id])
  end
end
