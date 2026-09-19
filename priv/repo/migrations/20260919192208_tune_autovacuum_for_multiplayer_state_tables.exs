defmodule HighSociety.Repo.Migrations.TuneAutovacuumForMultiplayerStateTables do
  use Ecto.Migration

  # Same fix as 20260919191649_tune_autovacuum_for_hot_small_tables, for the
  # two tables with the same shape of problem that hadn't shown up as
  # bloated yet only because they haven't seen much write volume in this
  # pre-launch period:
  #
  #   - poker_tournament_table_states gets an UPDATE on essentially every
  #     hand across every active tournament table, same as
  #     poker_table_states - except during a real MTT it'll hold many rows
  #     at once (one per table, consolidating down to a final table), not a
  #     fixed 3, so this one matters even more once a tournament is live.
  #   - battleship_match_states gets an UPDATE on every shot fired in every
  #     in-progress match.
  #
  # Postgres's default `50 + 20% of row count` autovacuum trigger is still
  # a poor fit here: these tables are small and short-lived per row (a
  # table/match closes and its row stops changing), so the fixed 50-tuple
  # floor dominates the same way it did for the other two.
  def change do
    execute(
      "ALTER TABLE poker_tournament_table_states SET (autovacuum_vacuum_scale_factor = 0.0, autovacuum_vacuum_threshold = 10)",
      "ALTER TABLE poker_tournament_table_states RESET (autovacuum_vacuum_scale_factor, autovacuum_vacuum_threshold)"
    )

    execute(
      "ALTER TABLE battleship_match_states SET (autovacuum_vacuum_scale_factor = 0.0, autovacuum_vacuum_threshold = 10)",
      "ALTER TABLE battleship_match_states RESET (autovacuum_vacuum_scale_factor, autovacuum_vacuum_threshold)"
    )
  end
end
