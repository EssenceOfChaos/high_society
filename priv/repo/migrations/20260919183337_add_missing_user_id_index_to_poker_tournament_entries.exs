defmodule HighSociety.Repo.Migrations.AddMissingUserIdIndexToPokerTournamentEntries do
  use Ecto.Migration

  def change do
    # 20260918161135_add_tournament_fields_to_poker_tournament_entries
    # dropped the original unique_index(:poker_tournament_entries, [:user_id])
    # for a composite [:tournament_id, :user_id] one, leaving user_id's own
    # `references(:users, on_delete: :delete_all)` fk with no index -
    # tournament_id being the composite index's leading column means Postgres
    # can't use it for a lookup on user_id alone (e.g. the cascade scan when
    # a users row is deleted). Caught via ecto_psql_extras' missing_fk_indexes
    # check on the LiveDashboard.
    create index(:poker_tournament_entries, [:user_id])
  end
end
