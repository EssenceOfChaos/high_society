defmodule HighSociety.Repo.Migrations.CreatePokerTournamentTableStates do
  use Ecto.Migration

  def change do
    create table(:poker_tournament_table_states) do
      add :slug, :string, null: false
      add :tournament_id, references(:poker_tournaments, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "active"
      add :seats, {:array, :map}, null: false, default: []
      add :button_seat, :integer
      add :hand, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:poker_tournament_table_states, [:slug])
    create index(:poker_tournament_table_states, [:tournament_id, :status])
  end
end
