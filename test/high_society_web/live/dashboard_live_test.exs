defmodule HighSocietyWeb.DashboardLiveTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts

  describe "activity tracking" do
    setup :register_and_log_in_user

    test "connecting bumps the user's active-days count and shows their badge", %{
      conn: conn,
      user: user
    } do
      assert user.active_days_count == 0

      {:ok, _view, html} = live(conn, ~p"/")

      assert Accounts.get_user!(user.id).active_days_count == 1
      assert html =~ ~s(data-tip="Novice")
      assert html =~ "images/badges/novice.png"
    end

    test "visiting a second page the same day does not double-count", %{conn: conn, user: user} do
      {:ok, _view, _html} = live(conn, ~p"/")
      {:ok, _view, _html} = live(conn, ~p"/games/war")

      assert Accounts.get_user!(user.id).active_days_count == 1
    end
  end

  test "lists War, Blackjack, and Poker as playable games", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "High Society"
    assert has_element?(view, "#game-card-war")
    assert has_element?(view, "#play-war")
    assert has_element?(view, "#game-card-blackjack")
    assert has_element?(view, "#play-blackjack")
    assert has_element?(view, "#game-card-poker")
    assert has_element?(view, "#play-poker")
  end

  test "the play links point at each game's route", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ~s(a#play-war[href="/games/war"]))
    assert has_element?(view, ~s(a#play-blackjack[href="/games/blackjack"]))
    assert has_element?(view, ~s(a#play-poker[href="/games/poker"]))
  end
end
