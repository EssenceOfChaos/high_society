defmodule HighSociety.Repo.Migrations.ConvertMoneyColumnsToCents do
  use Ecto.Migration

  @moduledoc """
  All money in the app used to be a whole-dollar integer ("chips"). From
  here on it's an integer number of cents (`HighSociety.Money`), so every
  existing dollar amount is scaled up x100 to keep its real value the same.

  Only top-level integer columns are touched here - `users.balance` and
  `battleship_match_states.wager`. Persisted jsonb game state (an
  in-progress Blackjack round's `hands`, or a Poker table's live hand) is
  not migrated: any such round or hand still open at deploy time will have
  stale, dollar-denominated numbers baked into its jsonb blob and should be
  allowed to finish (or be manually cleared) before this ships.
  """

  def up do
    execute "UPDATE users SET balance = balance * 100"
    execute "UPDATE battleship_match_states SET wager = wager * 100"
  end

  def down do
    execute "UPDATE battleship_match_states SET wager = wager / 100"
    execute "UPDATE users SET balance = balance / 100"
  end
end
