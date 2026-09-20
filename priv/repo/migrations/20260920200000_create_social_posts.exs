defmodule HighSociety.Repo.Migrations.CreateSocialPosts do
  use Ecto.Migration

  def change do
    create table(:social_posts) do
      add :platform, :string, null: false, default: "x"
      add :status, :string, null: false, default: "pending"
      add :source, :string, null: false
      add :body, :text, null: false
      add :tournament_id, references(:poker_tournaments, on_delete: :nilify_all)
      add :reviewed_by_user_id, references(:users, on_delete: :nilify_all)
      add :platform_post_id, :string
      add :posted_at, :utc_datetime
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:social_posts, [:status])
    create index(:social_posts, [:tournament_id])
  end
end
