defmodule HighSocietyWeb.GameLive.LeaderboardTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HighSociety.AccountsFixtures

  alias HighSociety.Accounts

  describe "Blackjack leaderboard" do
    test "redirects a guest to the log-in page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/games/blackjack/leaderboard")
    end

    test "shows an empty state when no one has played yet", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/games/blackjack/leaderboard")

      assert html =~ "Blackjack Leaderboard"
      assert html =~ "No one has played Blackjack yet"
    end

    test "lists ranked players with their badge, name, winnings, and tenure", %{conn: conn} do
      winner = user_fixture()
      {:ok, winner} = Accounts.update_user_display_name(winner, %{display_name: "Freddy"})
      {:ok, _} = Accounts.adjust_tokens_balance(winner, 1_000, "blackjack_payout")

      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/games/blackjack/leaderboard")

      assert html =~ "Freddy"
      assert html =~ "+1,000 Tokens"
      refute html =~ winner.email
    end
  end

  describe "Poker leaderboard" do
    test "renders under its own route without colliding with the table-slug route", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/games/poker/leaderboard")

      assert html =~ "Poker Leaderboard"
    end
  end
end
