defmodule HighSociety.Repo.Migrations.AddPokerSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :card_back, :string, null: false, default: "default"
      add :felt_color, :string, null: false, default: "green"
      # Nullable - unset means "neither", which keeps the existing
      # click-to-reveal button behavior for a non-showdown win. See
      # HighSociety.Games.Poker.showdown?/1.
      add :muck_preference, :string
    end
  end
end
