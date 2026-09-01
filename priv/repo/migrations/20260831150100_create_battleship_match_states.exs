defmodule HighSociety.Repo.Migrations.CreateBattleshipMatchStates do
  use Ecto.Migration

  def change do
    create table(:battleship_match_states) do
      add :slug, :string, null: false
      add :wager, :integer, null: false
      add :status, :string, null: false, default: "waiting_for_opponent"
      add :seat_0_user_id, references(:users, on_delete: :nilify_all)
      add :seat_1_user_id, references(:users, on_delete: :nilify_all)
      add :battleship, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:battleship_match_states, [:slug])
    create index(:battleship_match_states, [:status])
  end
end
