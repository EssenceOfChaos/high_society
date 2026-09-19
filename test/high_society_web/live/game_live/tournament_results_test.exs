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

  describe "KYC info" do
    setup %{user: admin} do
      previous = Application.get_env(:high_society, :admin_emails, [])
      on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
      Application.put_env(:high_society, :admin_emails, [admin.email])
      :ok
    end

    test "shows an admin the champion's KYC info, marked complete once every field is filled",
         %{conn: conn} do
      tournament = tournament_fixture()
      champion = user_fixture()

      {:ok, entry} =
        Tournaments.register(Scope.for_user(champion), tournament, %{
          "first_name" => "Jane",
          "last_name" => "Doe",
          "address" => "123 Main St",
          "city" => "Philadelphia",
          "state" => "PA",
          "zip_code" => "19102",
          "date_of_birth" => "1990-01-15"
        })

      entry
      |> PokerTournamentEntry.placement_changeset(%{finish_place: 1})
      |> HighSociety.Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/tournament/#{tournament.id}/results")

      assert html =~ "Jane Doe"
      assert html =~ "1990-01-15"
      assert html =~ "123 Main St"
      assert html =~ "Complete"
    end

    test "marks the champion's KYC info incomplete when only some fields are filled", %{
      conn: conn
    } do
      tournament = tournament_fixture()
      champion = user_fixture()

      {:ok, entry} =
        Tournaments.register(Scope.for_user(champion), tournament, %{"first_name" => "Jane"})

      entry
      |> PokerTournamentEntry.placement_changeset(%{finish_place: 1})
      |> HighSociety.Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/tournament/#{tournament.id}/results")

      assert html =~ "Incomplete"
    end

    test "never shows KYC info for a non-winner, even to an admin", %{conn: conn} do
      tournament = tournament_fixture()
      still_playing = user_fixture()

      {:ok, _entry} =
        Tournaments.register(Scope.for_user(still_playing), tournament, %{
          "first_name" => "Jane",
          "last_name" => "Doe"
        })

      {:ok, _view, html} = live(conn, ~p"/tournament/#{tournament.id}/results")

      refute html =~ "Jane Doe"
    end

    test "hides KYC info from a non-admin entirely", %{conn: conn} do
      Application.put_env(:high_society, :admin_emails, [])
      tournament = tournament_fixture()
      champion = user_fixture()

      {:ok, entry} =
        Tournaments.register(Scope.for_user(champion), tournament, %{
          "first_name" => "Jane",
          "last_name" => "Doe"
        })

      entry
      |> PokerTournamentEntry.placement_changeset(%{finish_place: 1})
      |> HighSociety.Repo.update!()

      {:ok, _view, html} = live(conn, ~p"/tournament/#{tournament.id}/results")

      refute html =~ "Jane Doe"
    end
  end
end
