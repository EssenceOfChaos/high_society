defmodule HighSociety.Repo.Migrations.AddClaimedRouletteChipsAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :claimed_roulette_chips_at, :utc_datetime
    end
  end
end
