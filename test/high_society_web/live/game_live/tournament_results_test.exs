defmodule HighSocietyWeb.GameLive.TournamentResultsTest do
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures

  alias HighSociety.Accounts.Scope
  alias HighSociety.Tournaments
  alias HighSociety.Tournaments.PokerTournamentEntry

  setup :register_and_log_in_user

  test "redirects a guest to the log-in page" do
    tournament = tournament_fixture()
    conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(conn, ~p"/tournament/#{tournament.id}/results")
  end

  test "lists standings, finished players first by place, hides Ethereum addresses from a non-admin",
       %{conn: conn} do
    tournament = tournament_fixture()

    champion = user_fixture()
    still_playing = user_fixture()

    {:ok, champion_entry} =
      Tournaments.register(Scope.for_user(champion), tournament, %{
        "ethereum_address" => "0x" <> String.duplicate("a", 40)
      })

    {:ok, _entry} = Tournaments.register(Scope.for_user(still_playing), tournament, %{})

    champion_entry
    |> PokerTournamentEntry.placement_changeset(%{finish_place: 1})
    |> HighSociety.Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/tournament/#{tournament.id}/results")

    assert html =~ HighSociety.Accounts.display_name(champion)
    assert html =~ HighSociety.Accounts.display_name(still_playing)
    assert html =~ "1st"
    assert html =~ "Still playing"
    refute html =~ String.duplicate("a", 40)
  end

  test "shows Ethereum addresses to an admin", %{conn: conn, user: admin} do
    previous = Application.get_env(:high_society, :admin_emails, [])
    on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
    Application.put_env(:high_society, :admin_emails, [admin.email])

    tournament = tournament_fixture()
    champion = user_fixture()
    address = "0x" <> String.duplicate("a", 40)

    {:ok, entry} =
      Tournaments.register(Scope.for_user(champion), tournament, %{"ethereum_address" => address})

    entry
    |> PokerTournamentEntry.placement_changeset(%{finish_place: 1})
    |> HighSociety.Repo.update!()

    {:ok, _view, html} = live(conn, ~p"/tournament/#{tournament.id}/results")

    assert html =~ address
  end
end
