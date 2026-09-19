defmodule HighSociety.Repo.Migrations.AddKycFieldsToPokerTournamentEntries do
  use Ecto.Migration

  def change do
    alter table(:poker_tournament_entries) do
      # All `:binary` - encrypted at rest via HighSociety.Vault (see
      # HighSociety.Encrypted.Binary/Date), never queried/filtered by
      # value, so no plaintext or blind-index columns are needed. See
      # HighSociety.Tournaments.PokerTournamentEntry.
      add :first_name, :binary
      add :last_name, :binary
      add :address, :binary
      add :city, :binary
      add :state, :binary
      add :zip_code, :binary
      add :date_of_birth, :binary
    end
  end
end
