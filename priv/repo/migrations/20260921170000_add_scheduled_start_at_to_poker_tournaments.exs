defmodule HighSociety.Repo.Migrations.AddScheduledStartAtToPokerTournaments do
  use Ecto.Migration

  def change do
    alter table(:poker_tournaments) do
      # The announced start time, shown as a countdown on the registration
      # page - distinct from `started_at`, which is only set once an admin
      # actually clicks "Start" (see HighSociety.Tournaments.start!/1).
      # Nullable: a tournament created before this feature, or one with no
      # announced time yet, simply shows no countdown.
      add :scheduled_start_at, :utc_datetime
    end
  end
end
