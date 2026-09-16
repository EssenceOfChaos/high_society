defmodule HighSociety.Repo.Migrations.AddInsuranceToBlackjackGames do
  use Ecto.Migration

  def change do
    alter table(:blackjack_games) do
      add :insurance_bet, :integer
      add :insurance_outcome, :string
    end
  end
end
