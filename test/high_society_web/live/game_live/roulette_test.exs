defmodule HighSocietyWeb.GameLive.RouletteTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts
  alias HighSociety.Games.RouletteGame
  alias HighSociety.Repo

  setup :register_and_log_in_user

  defp await_reveal(view) do
    Enum.reduce_while(1..50, nil, fn _, _ ->
      if has_element?(view, "#roulette-screen[data-spinning=false]") do
        {:halt, render(view)}
      else
        Process.sleep(5)
        {:cont, nil}
      end
    end)
  end

  test "redirects to log in when not authenticated" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/roulette")
  end

  test "shows the claim button pre-claim, and the updated balance post-claim", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/roulette")

    assert render(element(view, "#tokens-balance")) =~ "0 Tokens"
    assert has_element?(view, "#claim-roulette-tokens-button")

    view |> element("#claim-roulette-tokens-button") |> render_click()

    refute has_element?(view, "#claim-roulette-tokens-button")
    assert render(element(view, "#tokens-balance")) =~ "500,000 Tokens"
  end

  test "the spin button starts disabled until a bet is placed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/roulette")

    assert render(element(view, "#spin-button")) =~ "disabled"

    view |> element("#bet-cell-red") |> render_click()

    refute render(element(view, "#spin-button")) =~ "disabled"
  end

  test "clicking a cell places the selected chip, and clicking it again stacks it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/roulette")

    view |> element("#bet-cell-red") |> render_click()
    assert render(element(view, "#bet-cell-red")) =~ "100"
    assert render(element(view, "#roulette-screen")) =~ "Total bet:"

    view |> element("#chip-500") |> render_click()
    view |> element("#bet-cell-red") |> render_click()

    assert render(element(view, "#bet-cell-red")) =~ "600"
  end

  test "clear bets resets every pending bet", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/roulette")

    view |> element("#bet-cell-red") |> render_click()
    view |> element("#bet-cell-black") |> render_click()

    view |> element("#clear-bets-button") |> render_click()

    assert render(element(view, "#spin-button")) =~ "disabled"
    refute render(element(view, "#bet-cell-red")) =~ "bg-amber-500/90"
    refute render(element(view, "#bet-cell-black")) =~ "bg-amber-500/90"
  end

  test "spinning without enough balance shows an inline error and takes no chips", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/roulette")

    view |> element("#bet-cell-red") |> render_click()
    html = view |> element("#spin-button") |> render_click()

    assert html =~ "don&#39;t have enough Tokens"
  end

  test "a full spin debits the total stake, disables the button meanwhile, and reveals a result",
       %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/games/roulette")
    view |> element("#claim-roulette-tokens-button") |> render_click()

    view |> element("#bet-cell-red") |> render_click()
    view |> element("#bet-cell-straight-17") |> render_click()

    balance_before = Accounts.get_user!(user.id).tokens_balance

    html = view |> element("#spin-button") |> render_click()
    assert html =~ "disabled"

    await_reveal(view)

    updated_user = Accounts.get_user!(user.id)
    game = Repo.get_by!(RouletteGame, user_id: user.id)

    assert game.total_wager == 200
    assert game.winning_number in 0..36
    assert updated_user.tokens_balance == balance_before - 200 + game.total_payout
    assert has_element?(view, "#roulette-table")

    # bets are consumed by the spin, and the button resets for the next one
    assert render(element(view, "#spin-button")) =~ "disabled"
    refute render(element(view, "#bet-cell-red")) =~ "bg-amber-500/90"
    refute render(element(view, "#bet-cell-straight-17")) =~ "bg-amber-500/90"
  end

  test "rebet only appears after a spin, and restores exactly that spin's bets", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/games/roulette")
    view |> element("#claim-roulette-tokens-button") |> render_click()

    refute has_element?(view, "#rebet-button")

    view |> element("#bet-cell-red") |> render_click()
    view |> element("#chip-500") |> render_click()
    view |> element("#bet-cell-straight-17") |> render_click()

    view |> element("#spin-button") |> render_click()
    await_reveal(view)

    assert has_element?(view, "#rebet-button")

    view |> element("#rebet-button") |> render_click()

    assert render(element(view, "#bet-cell-red")) =~ "100"
    assert render(element(view, "#bet-cell-straight-17")) =~ "500"
    refute render(element(view, "#spin-button")) =~ "disabled"

    balance_before = Accounts.get_user!(user.id).tokens_balance
    view |> element("#spin-button") |> render_click()
    await_reveal(view)

    game = Repo.get_by!(RouletteGame, user_id: user.id)
    assert game.total_wager == 600

    assert Accounts.get_user!(user.id).tokens_balance ==
             balance_before - 600 + game.total_payout
  end
end
