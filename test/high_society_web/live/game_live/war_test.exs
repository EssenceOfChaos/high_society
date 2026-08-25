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

  test "flipping a card resolves a round and updates the piles", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/games/war")

    html = view |> element("#flip-button") |> render_click()

    assert html =~ "cards"
    refute html =~ "26 <span"

    persisted = Games.get_active_war_game(scope)
    assert persisted.round_number == 1
  end

  test "playing to completion shows the game result and lets you start a new game", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/games/war")

    html =
      Enum.reduce_while(1..500, nil, fn _, _ ->
        html = view |> element("#flip-button") |> render_click()

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
