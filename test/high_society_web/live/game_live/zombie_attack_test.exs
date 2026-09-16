defmodule HighSocietyWeb.GameLive.ZombieAttackTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts
  alias HighSociety.Games.ZombieAttack
  alias HighSociety.Tokens

  setup :register_and_log_in_user

  test "redirects to log in when not authenticated" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/zombie-attack")
  end

  test "shows a wager picker with no active game", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/zombie-attack")
    assert has_element?(view, "form[phx-submit='start_game']")
  end

  test "claiming the one-time tokens credits the balance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/zombie-attack")

    assert render(element(view, "#tokens-balance")) =~ "0 Tokens"
    view |> element("#claim-zombie-attack-tokens-button") |> render_click()

    refute has_element?(view, "#claim-zombie-attack-tokens-button")
    assert render(element(view, "#tokens-balance")) =~ "500,000 Tokens"
  end

  test "starting a game debits the wager", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_tokens_balance(user, 100_000, "test_funding")
    {:ok, view, _html} = live(conn, ~p"/games/zombie-attack")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "10000"})

    assert has_element?(view, "#zombie-canvas")
    assert render(element(view, "#tokens-balance")) =~ "90,000 Tokens"
  end

  test "rejects a wager over the max", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_tokens_balance(user, 100_000_000, "test_funding")
    {:ok, view, _html} = live(conn, ~p"/games/zombie-attack")

    view
    |> element("form[phx-submit='start_game']")
    |> render_submit(%{"wager" => Integer.to_string(ZombieAttack.max_wager() + 1)})

    assert render(view) =~ "max wager"
  end

  test "clearing all waves settles a full-clear win", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_tokens_balance(user, 100_000, "test_funding")
    {:ok, view, _html} = live(conn, ~p"/games/zombie-attack")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "10000"})

    for wave <- 1..ZombieAttack.wave_count() do
      render_hook(view, "wave_cleared", %{"wave" => wave})
    end

    payout = ZombieAttack.payout_for(10_000, :full_clear)

    assert render(view) =~ "You held the line!"
    assert render(view) =~ "#{Tokens.format(payout)} Tokens"
  end

  test "game over settles a loss with a partial payout", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_tokens_balance(user, 100_000, "test_funding")
    {:ok, view, _html} = live(conn, ~p"/games/zombie-attack")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "10000"})
    render_hook(view, "wave_cleared", %{"wave" => 1})
    render_hook(view, "wave_cleared", %{"wave" => 2})
    render_hook(view, "game_over", %{})

    assert render(view) =~ "The house has fallen."
    assert render(view) =~ "cleared 2/#{ZombieAttack.wave_count()} waves"
  end

  test "rejects an out-of-order wave checkpoint without mutating state", %{
    conn: conn,
    user: user
  } do
    {:ok, _user} = Accounts.adjust_tokens_balance(user, 100_000, "test_funding")
    {:ok, view, _html} = live(conn, ~p"/games/zombie-attack")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "10000"})
    render_hook(view, "wave_cleared", %{"wave" => 3})

    assert has_element?(view, "#zombie-canvas")
    assert render(element(view, "#tokens-balance")) =~ "90,000 Tokens"
  end

  test "play again resets to the wager picker", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_tokens_balance(user, 100_000, "test_funding")
    {:ok, view, _html} = live(conn, ~p"/games/zombie-attack")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "10000"})
    render_hook(view, "game_over", %{})
    view |> element("button", "Play again") |> render_click()

    assert has_element?(view, "form[phx-submit='start_game']")
  end
end
