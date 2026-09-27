defmodule HighSociety.Repo.Migrations.AddCountryToPokerTournamentEntries do
  use Ecto.Migration

  def change do
    alter table(:poker_tournament_entries) do
      # :binary - encrypted at rest via HighSociety.Vault, same as the other
      # KYC fields added in 20260919011832_add_kyc_fields_to_poker_tournament_entries.exs.
      add :country, :binary
    end
  end
end
