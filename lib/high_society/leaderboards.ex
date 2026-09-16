defmodule HighSociety.Leaderboards do
  @moduledoc """
  Per-game leaderboards, ranking players by lifetime net Tokens won at
  that game.

  "Net tokens won" sums every `HighSociety.Accounts.TokenTransaction`
  ledger row whose `source` belongs to that game (every bet, payout,
  buy-in, cash-out...), excluding the one-time starting grant - that's a
  gift, not winnings, and would flatter everyone's rank by the same fixed
  amount.

  For Blackjack this is an exact lifetime net (every bet/payout is
  written to the ledger synchronously as it happens - see
  `HighSociety.Games.debit_and_settle/5`). For Poker it's realized
  winnings only: `HighSociety.Games.PokerTable` only touches the ledger
  on `sit`/`stand` (`"poker_buy_in"`/`"poker_cash_out"`) - the chips won
  or lost hand-by-hand while currently seated live in that table's
  `PokerTableState` row, not here, so a player mid-session won't show
  their in-progress stack until they cash out.
  """

  import Ecto.Query

  alias HighSociety.Accounts
  alias HighSociety.Accounts.{TokenTransaction, User}
  alias HighSociety.Badges
  alias HighSociety.Repo

  @type game :: :blackjack | :poker

  @type entry :: %{
          rank: pos_integer(),
          user: User.t(),
          display_name: String.t(),
          net_tokens_won: integer(),
          badge: Badges.badge(),
          member_since: DateTime.t()
        }

  @source_prefix %{blackjack: "blackjack_%", poker: "poker_%"}
  @starting_grant %{blackjack: "starting_grant_blackjack", poker: "starting_grant_poker"}

  @doc """
  The top `limit` players for `game`, ranked highest net Tokens won
  first. Only players with at least one ledger entry for that game
  appear - never having played it isn't a rank of zero, it's not being
  on the board at all.
  """
  @spec top_players(game(), pos_integer()) :: [entry()]
  def top_players(game, limit \\ 100) when game in [:blackjack, :poker] do
    prefix = Map.fetch!(@source_prefix, game)
    starting_grant = Map.fetch!(@starting_grant, game)

    User
    |> join(:inner, [u], t in TokenTransaction, on: t.user_id == u.id)
    |> where([u, t], like(t.source, ^prefix) and t.source != ^starting_grant)
    |> group_by([u, t], u.id)
    |> order_by([u, t], desc: sum(t.amount))
    |> select([u, t], {u, sum(t.amount)})
    |> limit(^limit)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {{user, net_tokens_won}, rank} ->
      %{
        rank: rank,
        user: user,
        display_name: Accounts.display_name(user),
        net_tokens_won: net_tokens_won,
        badge: Badges.for_active_days(user.active_days_count),
        member_since: user.inserted_at
      }
    end)
  end
end
