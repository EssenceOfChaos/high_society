defmodule HighSociety.Repo.Migrations.AddActivityTrackingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :active_days_count, :integer, null: false, default: 0
      add :last_active_on, :date
    end
  end
end
