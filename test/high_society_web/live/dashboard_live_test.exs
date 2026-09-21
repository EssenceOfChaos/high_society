defmodule HighSocietyWeb.DashboardLiveTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HighSociety.TournamentsFixtures

  alias HighSociety.Accounts
  alias HighSociety.Tournaments

  describe "tournament announcement" do
    setup :register_and_log_in_user

    test "shown to a logged-in user who hasn't registered", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Poker Tournament — Coming Soon"
      assert html =~ "tournament-announcement-cta"
    end

    test "hidden once the user has registered", %{conn: conn, scope: scope} do
      tournament = tournament_fixture()
      {:ok, _entry} = Tournaments.register(scope, tournament, %{})

      {:ok, _view, html} = live(conn, ~p"/")

      refute html =~ "Poker Tournament — Coming Soon"
    end

    test "shown to a guest", %{} do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Poker Tournament — Coming Soon"
    end
  end

  describe "tournament countdown badge" do
    setup :register_and_log_in_user

    test "hidden when no tournament has an announced start time", %{conn: conn} do
      tournament_fixture()
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#tournament-countdown-badge")
    end

    test "shown poking out of the logo once a start time is announced", %{conn: conn} do
      tournament_fixture(%{scheduled_start_at: ~U[2026-10-30 21:00:00Z]})
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s(a#tournament-countdown-badge[data-tip="Poker Tournament"]))
      assert has_element?(view, ~s(a#tournament-countdown-badge[href="/tournament"]))
    end

    test "hidden to a guest with no tournament scheduled at all", %{} do
      conn = Phoenix.ConnTest.build_conn()
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#tournament-countdown-badge")
    end
  end

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
