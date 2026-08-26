defmodule HighSociety.Repo.Migrations.AddBalanceToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :balance, :integer, null: false, default: 0
      add :claimed_starting_chips_at, :utc_datetime
    end
  end
end
