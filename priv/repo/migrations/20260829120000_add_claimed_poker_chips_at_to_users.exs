defmodule HighSociety.Repo.Migrations.AddClaimedPokerChipsAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :claimed_poker_chips_at, :utc_datetime
    end
  end
end
