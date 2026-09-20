defmodule HighSociety.Repo.Migrations.CreateThreadsConnections do
  use Ecto.Migration

  def change do
    create table(:threads_connections) do
      add :threads_user_id, :string, null: false
      add :username, :string
      # `:binary` - encrypted at rest via HighSociety.Vault (see
      # HighSociety.Encrypted.Binary), same as the tournament KYC fields -
      # this token alone is enough to post as the connected account.
      add :access_token, :binary, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:threads_connections, [:threads_user_id])
  end
end
