defmodule HighSocietyWeb.GameLive.BlackjackTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts
  alias HighSociety.Games

  setup :register_and_log_in_user

  test "redirects to log in when not authenticated", %{conn: _conn} do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/blackjack")
  end

  test "shows the claim button pre-claim, and the updated balance post-claim", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    assert render(element(view, "#balance")) =~ "$0"
    assert has_element?(view, "#claim-chips-button")

    view |> element("#claim-chips-button") |> render_click()

    refute has_element?(view, "#claim-chips-button")
    assert render(element(view, "#balance")) =~ "$25,000"
  end

  test "chip buttons build up a pending bet, clamped at the $500 max", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    view |> element("#chip-0-100") |> render_click()
    assert render(element(view, "#bet-amount-0")) =~ "$100"

    for _ <- 1..5, do: view |> element("#chip-0-100") |> render_click()

    # 6 clicks of $100 would be $600, clamped down to the $500 max
    assert render(element(view, "#bet-amount-0")) =~ "$500"

    view |> element("#clear-bet-0") |> render_click()
    assert render(element(view, "#bet-amount-0")) =~ "$0"
    refute has_element?(view, "#clear-bet-0")
  end

  test "dealing with no claimed balance shows an inline error and creates no round", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    view |> element("#chip-0-25") |> render_click()
    html = view |> element("#deal-button") |> render_click()

    assert html =~ "don&#39;t have enough chips"
    assert Games.get_active_blackjack_game(scope) == nil
  end

  test "a bet over the $500 max is rejected server-side even bypassing the UI clamp", %{
    scope: scope
  } do
    {:ok, _user} = Accounts.claim_starting_chips(scope.user)
    scope = %{scope | user: Accounts.get_user!(scope.user.id)}

    assert {:error, :bet_too_large} = Games.start_blackjack_round(scope, %{0 => 9999})
    assert Games.get_active_blackjack_game(scope) == nil
  end

  test "a full round: place a bet, deal, hit/stand to conclusion, and balance updates", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    view |> element("#claim-chips-button") |> render_click()

    view |> element("#chip-0-25") |> render_click()
    html = view |> element("#deal-button") |> render_click()

    assert html =~ "Dealer"
    assert has_element?(view, "#hand-box-0")
    refute has_element?(view, "#betting-area")

    html =
      Enum.reduce_while(1..50, html, fn _, _ ->
        cond do
          has_element?(view, "#new-round-button") ->
            {:halt, render(view)}

          has_element?(view, "#stand-button-0") ->
            {:cont, view |> element("#stand-button-0") |> render_click()}

          true ->
            {:cont, render(view)}
        end
      end)

    assert html =~ "New round"

    updated_user = Accounts.get_user!(scope.user.id)
    game = Games.get_active_blackjack_game(scope)
    assert game.status == "round_over"

    total_payout = game.hands |> Enum.map(& &1["payout"]) |> Enum.sum()
    assert updated_user.balance == Accounts.starting_chip_amount() - 25 + total_payout
  end

  test "New round returns to the betting UI without touching the persisted round", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    view |> element("#claim-chips-button") |> render_click()
    view |> element("#chip-0-25") |> render_click()
    view |> element("#deal-button") |> render_click()

    Enum.reduce_while(1..50, nil, fn _, _ ->
      if has_element?(view, "#new-round-button") do
        {:halt, nil}
      else
        view |> element("#stand-button-0") |> render_click()
        {:cont, nil}
      end
    end)

    game_before = Games.get_active_blackjack_game(scope)
    html = view |> element("#new-round-button") |> render_click()

    assert has_element?(view, "#betting-area")
    assert html =~ "Deal"
    assert Games.get_active_blackjack_game(scope).id == game_before.id
    assert Games.get_active_blackjack_game(scope).status == game_before.status
  end
end
