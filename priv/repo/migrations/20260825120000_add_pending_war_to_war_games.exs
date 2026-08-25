defmodule HighSociety.Repo.Migrations.AddPendingWarToWarGames do
  use Ecto.Migration

  def change do
    alter table(:war_games) do
      add :pending_war, :map
    end
  end
end
