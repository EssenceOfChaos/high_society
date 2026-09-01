defmodule HighSociety.Repo.Migrations.AddClaimedBattleshipChipsAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :claimed_battleship_chips_at, :utc_datetime
    end
  end
end
