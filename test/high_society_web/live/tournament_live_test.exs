defmodule HighSocietyWeb.TournamentLiveTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HighSociety.TournamentsFixtures
  import Swoosh.TestAssertions

  setup :register_and_log_in_user

  setup %{user: user} do
    # register_and_log_in_user's user_fixture/1 call sends confirmation and
    # welcome emails - drain them so assert_email_sent below only ever sees
    # the tournament registration email (see the equivalent note in
    # HighSociety.TournamentsTest).
    assert_email_sent(to: user.email, subject: "Confirmation instructions")
    assert_email_sent(to: user.email, subject: "Welcome to HighSociety!")
    %{tournament: tournament_fixture()}
  end

  test "redirects a guest to the log-in page" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/tournament")
  end

  test "renders the registration form", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/tournament")

    assert html =~ "Poker Tournament"
    assert html =~ "Register for the tournament"
    refute html =~ "You&#39;re registered."
  end

  test "registering without an Ethereum address sends a confirmation email", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/tournament")

    html =
      view
      |> form("#tournament_form", %{"poker_tournament_entry" => %{"ethereum_address" => ""}})
      |> render_submit()

    assert html =~ "You&#39;re registered."
    assert html =~ "Update registration"

    assert_email_sent(
      to: user.email,
      subject: "You're registered for the High Society poker tournament"
    )
  end

  test "registering with a valid Ethereum address", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tournament")
    address = "0x" <> String.duplicate("a", 40)

    html =
      view
      |> form("#tournament_form", %{
        "poker_tournament_entry" => %{"ethereum_address" => address}
      })
      |> render_submit()

    assert html =~ "You&#39;re registered."
  end

  test "an invalid Ethereum address re-renders with an error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tournament")

    html =
      view
      |> form("#tournament_form", %{
        "poker_tournament_entry" => %{"ethereum_address" => "not-an-address"}
      })
      |> render_submit()

    assert html =~ "doesn&#39;t look like a valid Ethereum address"
    refute_email_sent()
  end

  test "revisiting after registering shows the registered state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tournament")

    view
    |> form("#tournament_form", %{"poker_tournament_entry" => %{"ethereum_address" => ""}})
    |> render_submit()

    {:ok, _view, html} = live(conn, ~p"/tournament")
    assert html =~ "You&#39;re registered."
    assert html =~ "Update registration"
  end

  test "shows an empty state when no tournament is scheduled", %{conn: conn} do
    HighSociety.Repo.update_all(HighSociety.Tournaments.PokerTournament,
      set: [status: "finished"]
    )

    {:ok, _view, html} = live(conn, ~p"/tournament")

    assert html =~ "No tournament is currently scheduled"
    refute html =~ "tournament_form"
  end
end
