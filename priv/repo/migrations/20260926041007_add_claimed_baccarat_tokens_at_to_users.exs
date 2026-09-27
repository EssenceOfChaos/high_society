defmodule HighSociety.Repo.Migrations.AddClaimedBaccaratTokensAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :claimed_baccarat_tokens_at, :utc_datetime
    end
  end
end
