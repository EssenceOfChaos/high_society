defmodule HighSocietyWeb.GameLive.TournamentTableTest do
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures

  alias HighSociety.Games.TournamentCoordinator

  setup :register_and_log_in_user

  test "redirects a guest to the log-in page" do
    tournament = tournament_fixture()

    conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/tournament/#{tournament.id}/tables/does-not-exist")
  end

  test "redirects to the lobby for a table that doesn't exist", %{conn: conn} do
    tournament = tournament_fixture()

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/tournament/#{tournament.id}/tables/does-not-exist")

    assert to == ~p"/tournament/#{tournament.id}/tables"
  end

  test "spectating shows the seated players", %{conn: conn} do
    tournament = tournament_fixture()
    users = for _ <- 1..2, do: user_fixture()
    tournament = start_tournament_for_test!(tournament, users)

    [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)

    {:ok, view, html} = live(conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")

    assert html =~ tournament.name
    assert has_element?(view, "#tournament-felt")
  end

  test "a seated player can fold on their turn", %{conn: conn, user: user} do
    tournament = tournament_fixture()
    other_user = user_fixture()
    tournament = start_tournament_for_test!(tournament, [user, other_user])

    [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)
    view_state = HighSociety.Games.TournamentTable.get_state(slug)
    acting_user_id = view_state.hand.seats[view_state.hand.action_on].user_id

    conn =
      if acting_user_id == user.id do
        conn
      else
        log_in_user(conn, other_user)
      end

    {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")

    view |> element("#fold-button") |> render_click()

    updated = HighSociety.Games.TournamentTable.get_state(slug)
    folded_seat = Enum.find(updated.hand.seats, fn {_i, s} -> s.user_id == acting_user_id end)
    assert elem(folded_seat, 1).status == :folded
  end
end
