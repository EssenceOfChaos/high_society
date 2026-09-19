defmodule HighSocietyWeb.AdminTokenTransactionsControllerTest do
  use HighSocietyWeb.ConnCase, async: false

  import HighSociety.AccountsFixtures

  alias HighSociety.Accounts

  setup :register_and_log_in_user

  setup do
    previous = Application.get_env(:high_society, :admin_emails, [])
    on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
    :ok
  end

  test "a non-admin gets a 403", %{conn: conn} do
    Application.put_env(:high_society, :admin_emails, [])

    conn = get(conn, ~p"/admin/token-transactions/export", %{"email" => "nobody@example.com"})

    assert conn.status == 403
  end

  test "an unknown email gets a 404", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    conn = get(conn, ~p"/admin/token-transactions/export", %{"email" => "nobody@example.com"})

    assert conn.status == 404
  end

  test "an admin downloads a player's full Token ledger as CSV", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    player = user_fixture()
    {:ok, player} = Accounts.adjust_tokens_balance(player, 1_000, "test_funding")
    {:ok, _player} = Accounts.adjust_tokens_balance(player, -250, "blackjack_bet", %{"hand" => 3})

    conn = get(conn, ~p"/admin/token-transactions/export", %{"email" => player.email})

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

    [{"content-disposition", disposition}] =
      Enum.filter(conn.resp_headers, fn {k, _v} -> k == "content-disposition" end)

    assert disposition =~ "attachment"
    assert disposition =~ ".csv"

    [header, blackjack_row, funding_row, ""] = String.split(conn.resp_body, "\r\n")
    assert header == "Time (UTC),Source,Amount,Metadata"
    assert blackjack_row =~ "blackjack_bet,-250,"
    assert blackjack_row =~ ~s("{""hand"":3}")
    assert funding_row =~ "test_funding,1000,{}"
  end

  test "filters the export by source when given", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    player = user_fixture()
    {:ok, player} = Accounts.adjust_tokens_balance(player, 1_000, "test_funding")
    {:ok, _player} = Accounts.adjust_tokens_balance(player, -250, "blackjack_bet")

    conn =
      get(conn, ~p"/admin/token-transactions/export", %{
        "email" => player.email,
        "source" => "blackjack_bet"
      })

    assert conn.resp_body =~ "blackjack_bet"
    refute conn.resp_body =~ "test_funding"
  end
end
