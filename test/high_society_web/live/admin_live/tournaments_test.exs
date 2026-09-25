defmodule HighSocietyWeb.AdminLive.TournamentsTest do
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures

  alias HighSociety.Accounts.Scope
  alias HighSociety.Tournaments

  setup :register_and_log_in_user

  setup do
    previous = Application.get_env(:high_society, :admin_emails, [])
    on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
    :ok
  end

  test "redirects a guest to the log-in page" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/tournaments")
  end

  test "redirects a non-admin user away with a flash", %{conn: conn} do
    Application.put_env(:high_society, :admin_emails, [])

    assert {:error, redirect} = live(conn, ~p"/admin/tournaments")
    assert {:redirect, %{to: "/", flash: flash}} = redirect
    assert flash["error"] =~ "don't have access"
  end

  test "an admin can create a tournament using the default schedule", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    {:ok, view, _html} = live(conn, ~p"/admin/tournaments")

    html =
      view
      |> form("#tournament_form", %{"poker_tournament" => %{"name" => "Friday Night Freeroll"}})
      |> render_submit()

    assert html =~ "Friday Night Freeroll"
    assert html =~ "scheduled"

    tournament = Tournaments.list_tournaments() |> List.first()
    assert tournament.name == "Friday Night Freeroll"
    assert tournament.starting_stack == 10_000
    assert length(tournament.blind_levels) == 15
  end

  test "an admin can set an announced start time, shown in the tournament list", %{
    conn: conn,
    user: admin
  } do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    {:ok, view, _html} = live(conn, ~p"/admin/tournaments")

    html =
      view
      |> form("#tournament_form", %{
        "poker_tournament" => %{
          "name" => "Scheduled Freeroll",
          "scheduled_start_at" => "2026-10-30T21:00"
        }
      })
      |> render_submit()

    tournament = Tournaments.list_tournaments() |> List.first()
    assert tournament.scheduled_start_at == ~U[2026-10-30 21:00:00Z]
    assert html =~ "Oct 30, 2026 9:00 PM UTC"
  end

  test "a tournament with no announced start time shows a placeholder", %{
    conn: conn,
    user: admin
  } do
    Application.put_env(:high_society, :admin_emails, [admin.email])
    tournament_fixture(%{name: "No Announced Time"})

    {:ok, _view, html} = live(conn, ~p"/admin/tournaments")

    assert html =~ "No Announced Time"
    assert html =~ "—"
  end

  test "re-renders with an error for an invalid tournament", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    {:ok, view, _html} = live(conn, ~p"/admin/tournaments")

    html =
      view
      |> form("#tournament_form", %{"poker_tournament" => %{"name" => ""}})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
  end

  test "starting a tournament with enough entrants flips it to running", %{
    conn: conn,
    user: admin
  } do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    tournament = tournament_fixture(%{name: "Ready To Start"})

    Enum.each(1..2, fn _ ->
      Tournaments.register(Scope.for_user(user_fixture()), tournament, %{})
    end)

    stop_tournament_after_test!(tournament.id)

    {:ok, view, _html} = live(conn, ~p"/admin/tournaments")

    html =
      view
      |> element("#start-tournament-#{tournament.id}")
      |> render_click()

    assert html =~ "is running"
    assert Tournaments.get_tournament!(tournament.id).status == "running"
    refute has_element?(view, "#start-tournament-#{tournament.id}")
  end

  test "starting a tournament without enough entrants shows an error", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    tournament = tournament_fixture(%{name: "Not Enough Players"})

    {:ok, view, _html} = live(conn, ~p"/admin/tournaments")

    html =
      view
      |> element("#start-tournament-#{tournament.id}")
      |> render_click()

    assert html =~ "at least 2 registered entrants"
    assert Tournaments.get_tournament!(tournament.id).status == "scheduled"
  end
end
