defmodule HighSociety.Repo.Migrations.CreatePokerTournamentEntries do
  use Ecto.Migration

  def change do
    create table(:poker_tournament_entries) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Opt-in, not required to enter - see HighSociety.Tournaments.PokerTournamentEntry.
      # No cash/crypto ever moves through the app itself; this is only where a winner
      # would like a manual payout sent, decided and executed entirely outside the app.
      add :ethereum_address, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:poker_tournament_entries, [:user_id])
  end
end
