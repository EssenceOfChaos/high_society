defmodule HighSociety.Repo.Migrations.AddDisplayNameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # citext (already enabled for :email - see create_users_auth_tables)
      # so uniqueness is case-insensitive: "Freddy" and "freddy" collide.
      # Nullable - a user who hasn't set one yet falls back to their
      # email-derived name (see HighSociety.Games.PokerTable.username/1).
      add :display_name, :citext
    end

    create unique_index(:users, [:display_name])
  end
end
