defmodule HighSociety.Repo.Migrations.AddClaimedSlotsChipsAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :claimed_slots_chips_at, :utc_datetime
    end
  end
end
