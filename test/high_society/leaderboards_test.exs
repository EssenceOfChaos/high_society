defmodule HighSociety.LeaderboardsTest do
  use HighSociety.DataCase, async: true

  alias HighSociety.Accounts
  alias HighSociety.Leaderboards

  import HighSociety.AccountsFixtures

  defp funded_user(tokens_balance \\ 100_000) do
    user = user_fixture()
    {:ok, user} = Accounts.adjust_tokens_balance(user, tokens_balance, "test_funding")
    user
  end

  describe "top_players/2" do
    test "ranks players by net tokens won, highest first" do
      big_winner = funded_user()
      small_winner = funded_user()

      {:ok, _} = Accounts.adjust_tokens_balance(big_winner, -1_000, "blackjack_bet")
      {:ok, _} = Accounts.adjust_tokens_balance(big_winner, 3_000, "blackjack_payout")

      {:ok, _} = Accounts.adjust_tokens_balance(small_winner, -1_000, "blackjack_bet")
      {:ok, _} = Accounts.adjust_tokens_balance(small_winner, 1_500, "blackjack_payout")

      assert [first, second] = Leaderboards.top_players(:blackjack)
      assert first.rank == 1
      assert first.user.id == big_winner.id
      assert first.net_tokens_won == 2_000
      assert second.rank == 2
      assert second.user.id == small_winner.id
      assert second.net_tokens_won == 500
    end

    test "excludes the one-time starting grant from net winnings" do
      user = user_fixture()
      {:ok, _} = Accounts.adjust_tokens_balance(user, 500_000, "starting_grant_blackjack")
      {:ok, _} = Accounts.adjust_tokens_balance(user, -1_000, "blackjack_bet")
      {:ok, _} = Accounts.adjust_tokens_balance(user, 1_500, "blackjack_payout")

      assert [entry] = Leaderboards.top_players(:blackjack)
      assert entry.net_tokens_won == 500
    end

    test "never having played isn't a rank of zero - the player just doesn't appear" do
      user_fixture()
      assert Leaderboards.top_players(:blackjack) == []
    end

    test "keeps blackjack and poker winnings separate" do
      user = user_fixture()
      {:ok, _} = Accounts.adjust_tokens_balance(user, 1_000, "blackjack_payout")
      {:ok, _} = Accounts.adjust_tokens_balance(user, 2_000, "poker_cash_out")

      assert [blackjack_entry] = Leaderboards.top_players(:blackjack)
      assert blackjack_entry.net_tokens_won == 1_000

      assert [poker_entry] = Leaderboards.top_players(:poker)
      assert poker_entry.net_tokens_won == 2_000
    end

    test "includes the display name, badge, and member-since date" do
      user = user_fixture()
      {:ok, user} = Accounts.update_user_display_name(user, %{display_name: "Freddy"})
      {:ok, _} = Accounts.adjust_tokens_balance(user, 1_000, "blackjack_payout")

      assert [entry] = Leaderboards.top_players(:blackjack)
      assert entry.display_name == "Freddy"
      assert entry.badge.slug == "novice"
      assert entry.member_since == user.inserted_at
    end

    test "falls back to the email-derived name when no display name is set" do
      user = user_fixture()
      {:ok, _} = Accounts.adjust_tokens_balance(user, 1_000, "blackjack_payout")

      assert [entry] = Leaderboards.top_players(:blackjack)
      assert entry.display_name == user.email |> String.split("@") |> hd()
    end

    test "respects the limit" do
      for _ <- 1..3 do
        user = user_fixture()
        {:ok, _} = Accounts.adjust_tokens_balance(user, 1_000, "blackjack_payout")
      end

      assert length(Leaderboards.top_players(:blackjack, 2)) == 2
    end
  end
end
