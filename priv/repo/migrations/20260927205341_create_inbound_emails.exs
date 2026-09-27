defmodule HighSociety.Repo.Migrations.CreateInboundEmails do
  use Ecto.Migration

  def change do
    create table(:inbound_emails) do
      add :from_name, :string, null: false
      add :from_email, :string, null: false
      add :subject, :string
      add :body, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :suggested_category, :string
      add :draft_reply, :text
      add :reviewed_by_user_id, references(:users, on_delete: :nilify_all)
      add :sent_at, :utc_datetime
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:inbound_emails, [:status])
  end
end
