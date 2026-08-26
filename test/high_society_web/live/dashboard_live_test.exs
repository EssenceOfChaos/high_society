defmodule HighSocietyWeb.DashboardLiveTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "lists War and Blackjack as playable games", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "High Society"
    assert has_element?(view, "#game-card-war")
    assert has_element?(view, "#play-war")
    assert has_element?(view, "#game-card-blackjack")
    assert has_element?(view, "#play-blackjack")
  end

  test "shows unreleased games as coming soon without a play link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#game-card-poker button:disabled", "Coming soon")
    refute has_element?(view, "#play-poker")
  end

  test "the play links point at each game's route", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ~s(a#play-war[href="/games/war"]))
    assert has_element?(view, ~s(a#play-blackjack[href="/games/blackjack"]))
  end
end
