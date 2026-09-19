defmodule HighSociety.Repo.Migrations.TuneAutovacuumForHotSmallTables do
  use Ecto.Migration

  # Postgres's default autovacuum trigger is `50 + 20% of row count` dead
  # tuples. That's fine for most tables, but poker_table_states (3 rows,
  # one per cash table) and battleship_games (one row per solo player,
  # still small) each get an UPDATE on essentially every game action -
  # every hand, every shot - so the 20% term is negligible and the fixed
  # 50-tuple floor dominates regardless of how tiny the table actually is.
  # Result (confirmed via the ecto_psql_extras bloat/vacuum_stats pages on
  # the LiveDashboard): both sawtooth between ~0 and ~90% bloat rather than
  # staying low, and poker_table_states in particular sits right at that
  # 50-tuple floor for days at a time. Lowering the threshold - and
  # zeroing out the scale factor, since it's irrelevant at this row count
  # anyway - makes autovacuum reclaim dead tuples continuously instead of
  # waiting for a generic floor that was never sized for a 3-row table.
  # Vacuuming a table this small is essentially free, so there's no
  # meaningful tradeoff being made here.
  def change do
    execute(
      "ALTER TABLE poker_table_states SET (autovacuum_vacuum_scale_factor = 0.0, autovacuum_vacuum_threshold = 10)",
      "ALTER TABLE poker_table_states RESET (autovacuum_vacuum_scale_factor, autovacuum_vacuum_threshold)"
    )

    execute(
      "ALTER TABLE battleship_games SET (autovacuum_vacuum_scale_factor = 0.0, autovacuum_vacuum_threshold = 10)",
      "ALTER TABLE battleship_games RESET (autovacuum_vacuum_scale_factor, autovacuum_vacuum_threshold)"
    )
  end
end
