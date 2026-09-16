defmodule HighSociety.Repo.Migrations.AddClaimedZombieAttackChipsAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :claimed_zombie_attack_chips_at, :utc_datetime
    end
  end
end
