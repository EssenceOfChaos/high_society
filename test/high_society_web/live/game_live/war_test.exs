defmodule HighSocietyWeb.GameLive.WarTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Games

  setup :register_and_log_in_user

  test "redirects to log in when not authenticated", %{conn: _conn} do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/war")
  end

  test "deals a fresh game on first visit and shows both piles", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/war")

    assert has_element?(view, "#war-table")
    assert render(view) =~ "26"
    assert has_element?(view, "#flip-button")
  end

  test "shows a status bar reflecting each side's share of the deck", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/war")

    assert has_element?(view, "#status-bar")
    html = render(view)
    assert html =~ "You — 26 cards"
    assert html =~ "Computer — 26 cards"
    assert html =~ "neck and neck"

    html = view |> element("#flip-button") |> render_click()
    refute html =~ "You — 26 cards"
  end

  test "flipping a card resolves a round and updates the piles", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/games/war")

    html = view |> element("#flip-button") |> render_click()

    assert html =~ "cards"
    refute html =~ "26 <span"

    persisted = Games.get_active_war_game(scope)
    assert persisted.round_number == 1
  end

  test "a tie declares war and requires a separate click to flip the tiebreaker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/war")

    html =
      Enum.reduce_while(1..500, nil, fn _, _ ->
        html = view |> element("#flip-button") |> render_click()

        if has_element?(view, "#flip-tiebreaker-button") do
          {:halt, html}
        else
          {:cont, html}
        end
      end)

    assert html =~ "War!"
    refute has_element?(view, "#flip-button")
    assert has_element?(view, "#flip-tiebreaker-button")

    # the tiebreaker itself can tie again, chaining into another war, so keep
    # flipping tiebreakers until one finally resolves it
    html =
      Enum.reduce_while(1..20, nil, fn _, _ ->
        html = view |> element("#flip-tiebreaker-button") |> render_click()

        if has_element?(view, "#flip-tiebreaker-button") do
          {:cont, html}
        else
          {:halt, html}
        end
      end)

    refute has_element?(view, "#flip-tiebreaker-button")
    assert html =~ "cards" or html =~ "won"
  end

  test "playing to completion shows the game result and lets you start a new game", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/games/war")

    html =
      Enum.reduce_while(1..3000, nil, fn _, _ ->
        button = if has_element?(view, "#flip-tiebreaker-button"), do: "#flip-tiebreaker-button", else: "#flip-button"
        html = view |> element(button) |> render_click()

        if has_element?(view, "#game-result") do
          {:halt, html}
        else
          {:cont, html}
        end
      end)

    assert html =~ "won"
    assert has_element?(view, "#play-again-button")

    html = view |> element("#play-again-button") |> render_click()
    assert html =~ "26"
    assert has_element?(view, "#flip-button")
  end
end
