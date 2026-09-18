defmodule HighSociety.Repo.Migrations.AddTournamentFieldsToPokerTournamentEntries do
  use Ecto.Migration

  def change do
    alter table(:poker_tournament_entries) do
      add :tournament_id, references(:poker_tournaments, on_delete: :delete_all)
      add :bought_in_at, :utc_datetime
      add :eliminated_at, :utc_datetime
      add :finish_place, :integer
    end

    # Was a single flat pool (one entry per user, ever) - now scoped per
    # tournament run, so the same user can register for multiple
    # tournaments over time but only once each.
    drop unique_index(:poker_tournament_entries, [:user_id])
    create unique_index(:poker_tournament_entries, [:tournament_id, :user_id])
    create index(:poker_tournament_entries, [:tournament_id, :finish_place])
  end
end
