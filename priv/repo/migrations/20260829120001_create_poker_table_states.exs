defmodule HighSociety.Repo.Migrations.CreatePokerTableStates do
  use Ecto.Migration

  def change do
    create table(:poker_table_states) do
      add :slug, :string, null: false
      add :seats, {:array, :map}, null: false, default: []
      add :button_seat, :integer
      add :hand, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:poker_table_states, [:slug])
  end
end
