defmodule HighSocietyWeb.TokensLiveTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "is reachable without logging in", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/tokens")

    assert html =~ "High Society"
    assert html =~ "Tokens"
  end

  test "explains what Tokens are, how they're earned, and how they're redeemed", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/tokens")

    assert html =~ "What&#39;s a"
    assert html =~ "How you"
    assert html =~ "earn"
    assert html =~ "Where they"
    assert html =~ "starting stake"
    assert html =~ "Token store is coming soon"
  end

  test "shows a guest register/log-in CTA, not the logged-in one", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/tokens")

    assert html =~ "Create an account"
    refute html =~ "Browse the tables"
  end

  test "shows a logged-in CTA back to the games, not the guest one", %{conn: conn} do
    conn = log_in_user(conn, HighSociety.AccountsFixtures.user_fixture())
    {:ok, _view, html} = live(conn, ~p"/tokens")

    assert html =~ "Browse the tables"
    refute html =~ "Create an account"
  end

  test "the footer links here from every page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(href="/tokens")
  end
end
