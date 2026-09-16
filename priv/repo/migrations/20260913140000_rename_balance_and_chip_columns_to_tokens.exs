defmodule HighSociety.Repo.Migrations.RenameBalanceAndChipColumnsToTokens do
  use Ecto.Migration

  def change do
    rename table(:users), :balance, to: :tokens_balance
    rename table(:users), :claimed_starting_chips_at, to: :claimed_blackjack_tokens_at
    rename table(:users), :claimed_battleship_chips_at, to: :claimed_battleship_tokens_at
    rename table(:users), :claimed_poker_chips_at, to: :claimed_poker_tokens_at
    rename table(:users), :claimed_slots_chips_at, to: :claimed_slots_tokens_at
    rename table(:users), :claimed_roulette_chips_at, to: :claimed_roulette_tokens_at
    rename table(:users), :claimed_zombie_attack_chips_at, to: :claimed_zombie_attack_tokens_at
  end
end
