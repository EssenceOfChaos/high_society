defmodule HighSociety.Repo.Migrations.CreatePostsTable do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string
      add :content, :text
      add :likes, :integer
      add :user_id, references(:users)

      timestamps()
    end

  end
end
