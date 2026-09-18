defmodule HighSociety.Repo.Migrations.CreatePokerTournaments do
  use Ecto.Migration

  def change do
    create table(:poker_tournaments) do
      add :name, :string, null: false
      add :status, :string, null: false, default: "scheduled"

      add :starting_stack, :integer, null: false
      add :level_minutes, :integer, null: false
      add :break_every_minutes, :integer, null: false
      add :break_minutes, :integer, null: false
      add :late_registration_minutes, :integer, null: false

      # Snapshotted at creation from `HighSociety.Games.TournamentBlinds` -
      # a later code change to the default schedule must never retroactively
      # alter a tournament that's already scheduled/running/finished.
      add :blind_levels, {:array, :map}, null: false

      add :current_level, :integer, null: false, default: 1
      add :level_started_at, :utc_datetime
      add :on_break, :boolean, null: false, default: false
      add :break_ends_at, :utc_datetime

      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:poker_tournaments, [:status])
  end
end
