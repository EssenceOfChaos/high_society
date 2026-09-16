defmodule HighSocietyWeb.AdminLive.TokenTransactionsTest do
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts

  setup :register_and_log_in_user

  setup do
    previous = Application.get_env(:high_society, :admin_emails, [])
    on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
    :ok
  end

  test "redirects a guest to the log-in page" do
    conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/admin/token-transactions")
  end

  test "redirects a non-admin user away with a flash", %{conn: conn} do
    Application.put_env(:high_society, :admin_emails, [])

    assert {:error, redirect} = live(conn, ~p"/admin/token-transactions")
    assert {:redirect, %{to: "/", flash: flash}} = redirect
    assert flash["error"] =~ "don't have access"
  end

  test "an admin can look up a player's Token history by email", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    player = HighSociety.AccountsFixtures.user_fixture()
    {:ok, player} = Accounts.adjust_tokens_balance(player, 1_000, "test_funding")
    {:ok, _player} = Accounts.adjust_tokens_balance(player, -250, "blackjack_bet")

    {:ok, view, _html} = live(conn, ~p"/admin/token-transactions")

    view |> form("form", %{email: player.email, source: ""}) |> render_submit()

    html = render(view)
    assert html =~ player.email
    assert html =~ "750 Tokens"
    assert html =~ "test_funding"
    assert html =~ "blackjack_bet"
    assert html =~ "+1,000 Tokens"
    assert html =~ "-250 Tokens"
  end

  test "filters by source when given", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    player = HighSociety.AccountsFixtures.user_fixture()
    {:ok, player} = Accounts.adjust_tokens_balance(player, 1_000, "test_funding")
    {:ok, _player} = Accounts.adjust_tokens_balance(player, -250, "blackjack_bet")

    {:ok, view, _html} = live(conn, ~p"/admin/token-transactions")

    view |> form("form", %{email: player.email, source: "blackjack_bet"}) |> render_submit()

    html = render(view)
    assert html =~ "blackjack_bet"
    refute html =~ "test_funding"
  end

  test "shows an error for an email with no matching player", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    {:ok, view, _html} = live(conn, ~p"/admin/token-transactions")

    view
    |> form("form", %{email: "nobody@example.com", source: ""})
    |> render_submit()

    assert render(element(view, "#admin-not-found")) =~ "nobody@example.com"
  end
end
