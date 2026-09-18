defmodule HighSocietyWeb.GameLive.TournamentTablesTest do
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
             live(conn, ~p"/tournament/#{tournament.id}/tables")
  end

  test "shows an empty state when the tournament isn't running", %{conn: conn} do
    tournament = tournament_fixture()

    {:ok, _view, html} = live(conn, ~p"/tournament/#{tournament.id}/tables")

    assert html =~ "isn&#39;t running"
  end

  test "lists active tables with seat counts once running", %{conn: conn} do
    tournament = tournament_fixture()
    users = for _ <- 1..3, do: user_fixture()
    tournament = start_tournament_for_test!(tournament, users)

    {:ok, view, html} = live(conn, ~p"/tournament/#{tournament.id}/tables")

    assert html =~ "Level 1"
    assert html =~ "3 remaining"

    [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)
    assert has_element?(view, "#tournament-table-#{slug}", "3 / 8")
  end

  test "live-updates as the coordinator broadcasts", %{conn: conn} do
    tournament = tournament_fixture()
    users = for _ <- 1..2, do: user_fixture()
    tournament = start_tournament_for_test!(tournament, users)

    {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables")

    updated_view = %{
      current_level: 2,
      small_blind: 150,
      big_blind: 300,
      on_break: false,
      remaining: 2,
      tables: TournamentCoordinator.get_state(tournament.id).tables
    }

    send(view.pid, {:tournament_updated, updated_view})

    assert render(view) =~ "Level 2"
  end
end
