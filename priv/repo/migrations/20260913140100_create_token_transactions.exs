defmodule HighSociety.Repo.Migrations.CreateTokenTransactions do
  use Ecto.Migration

  def change do
    create table(:token_transactions) do
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :amount, :integer, null: false
      add :source, :string, size: 50, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:token_transactions, [:user_id])
    create index(:token_transactions, [:source])
  end
end
