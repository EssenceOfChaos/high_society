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

  describe "countdown" do
    test "hidden when the tournament has no announced start time", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/tournament")

      refute html =~ "Tournament starts in"
      refute has_element?(view, "#tournament-countdown")
    end

    test "shown for a scheduled tournament with an announced start time", %{
      conn: conn,
      tournament: tournament
    } do
      tournament
      |> HighSociety.Tournaments.PokerTournament.changeset(%{
        scheduled_start_at: ~U[2026-10-30 21:00:00Z]
      })
      |> HighSociety.Repo.update!()

      {:ok, view, html} = live(conn, ~p"/tournament")

      assert html =~ "Tournament starts in"
      assert has_element?(view, "#tournament-countdown")
    end
  end

  describe "KYC fields" do
    test "renders alongside the Ethereum address field, all optional", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tournament")

      assert has_element?(view, "input[name='poker_tournament_entry[first_name]']")
      assert has_element?(view, "input[name='poker_tournament_entry[last_name]']")
      assert has_element?(view, "input[name='poker_tournament_entry[address]']")
      assert has_element?(view, "select[name='poker_tournament_entry[country]']")
      assert has_element?(view, "input[name='poker_tournament_entry[city]']")
      assert has_element?(view, "input[name='poker_tournament_entry[zip_code]']")
      assert has_element?(view, "input[name='poker_tournament_entry[date_of_birth]']")
    end

    test "defaults Country to the US, rendering State as a dropdown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tournament")

      assert has_element?(view, "select[name='poker_tournament_entry[state]']")

      assert has_element?(
               view,
               "select[name='poker_tournament_entry[country]'] option[value='US'][selected]"
             )
    end

    test "switches State to a province dropdown when Country is changed to Canada", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/tournament")

      html =
        view
        |> form("#tournament_form", %{"poker_tournament_entry" => %{"country" => "CA"}})
        |> render_change()

      assert has_element?(view, "select[name='poker_tournament_entry[state]']")
      assert html =~ "Province"
      assert html =~ "Ontario"
    end

    test "renders State as free-text 'Region' when Country is Other", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tournament")

      html =
        view
        |> form("#tournament_form", %{"poker_tournament_entry" => %{"country" => "OTHER"}})
        |> render_change()

      refute has_element?(view, "select[name='poker_tournament_entry[state]']")
      assert has_element?(view, "input[name='poker_tournament_entry[state]']")
      assert html =~ "Region"
    end

    test "tabbing off the ZIP field autofills City and State (Country defaults to US)", %{
      conn: conn
    } do
      Req.Test.stub(HighSociety.Tournaments.Zippopotamus, fn conn ->
        assert conn.request_path == "/us/19406"

        Req.Test.json(conn, %{
          "places" => [%{"place name" => "King Of Prussia", "state abbreviation" => "PA"}]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/tournament")

      html =
        view
        |> element("input[name='poker_tournament_entry[zip_code]']")
        |> render_blur(%{"value" => "19406"})

      assert has_element?(
               view,
               "select[name='poker_tournament_entry[state]'] option[value='PA'][selected]"
             )

      assert html =~ "King Of Prussia"
    end

    test "a second, different ZIP re-triggers autofill instead of getting stuck on the first result",
         %{conn: conn} do
      Req.Test.stub(HighSociety.Tournaments.Zippopotamus, fn conn ->
        case conn.request_path do
          "/us/19406" ->
            Req.Test.json(conn, %{
              "places" => [%{"place name" => "King Of Prussia", "state abbreviation" => "PA"}]
            })

          "/us/10001" ->
            Req.Test.json(conn, %{
              "places" => [%{"place name" => "New York", "state abbreviation" => "NY"}]
            })
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/tournament")

      view
      |> element("input[name='poker_tournament_entry[zip_code]']")
      |> render_blur(%{"value" => "19406"})

      assert has_element?(
               view,
               "input[name='poker_tournament_entry[city]'][value='King Of Prussia']"
             )

      html =
        view
        |> element("input[name='poker_tournament_entry[zip_code]']")
        |> render_blur(%{"value" => "10001"})

      assert has_element?(view, "input[name='poker_tournament_entry[city]'][value='New York']")

      assert has_element?(
               view,
               "select[name='poker_tournament_entry[state]'] option[value='NY'][selected]"
             )

      assert html =~ "New York"
    end

    test "a manual edit after autofill is preserved on a later ZIP lookup", %{conn: conn} do
      Req.Test.stub(HighSociety.Tournaments.Zippopotamus, fn conn ->
        Req.Test.json(conn, %{
          "places" => [%{"place name" => "King Of Prussia", "state abbreviation" => "PA"}]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/tournament")

      view
      |> element("input[name='poker_tournament_entry[zip_code]']")
      |> render_blur(%{"value" => "19406"})

      assert has_element?(
               view,
               "input[name='poker_tournament_entry[city]'][value='King Of Prussia']"
             )

      view
      |> form("#tournament_form", %{"poker_tournament_entry" => %{"city" => "Villanova"}})
      |> render_change()

      view
      |> element("input[name='poker_tournament_entry[zip_code]']")
      |> render_blur(%{"value" => "19406"})

      assert has_element?(view, "input[name='poker_tournament_entry[city]'][value='Villanova']")
    end

    test "does not overwrite a City/State the player already typed", %{conn: conn} do
      Req.Test.stub(HighSociety.Tournaments.Zippopotamus, fn conn ->
        Req.Test.json(conn, %{
          "places" => [%{"place name" => "King Of Prussia", "state abbreviation" => "PA"}]
        })
      end)

      {:ok, view, _html} = live(conn, ~p"/tournament")

      view
      |> form("#tournament_form", %{
        "poker_tournament_entry" => %{"city" => "Philadelphia", "state" => "NY"}
      })
      |> render_change()

      view
      |> element("input[name='poker_tournament_entry[zip_code]']")
      |> render_blur(%{"value" => "19406"})

      assert has_element?(
               view,
               "input[name='poker_tournament_entry[city]'][value='Philadelphia']"
             )

      assert has_element?(
               view,
               "select[name='poker_tournament_entry[state]'] option[value='NY'][selected]"
             )
    end

    test "does nothing when Country is Other", %{conn: conn} do
      Req.Test.stub(HighSociety.Tournaments.Zippopotamus, fn _conn ->
        flunk("should never look up a ZIP code outside US/CA/MX")
      end)

      {:ok, view, _html} = live(conn, ~p"/tournament")

      view
      |> form("#tournament_form", %{"poker_tournament_entry" => %{"country" => "OTHER"}})
      |> render_change()

      view
      |> element("input[name='poker_tournament_entry[zip_code]']")
      |> render_blur(%{"value" => "75001"})

      assert has_element?(view, "input[name='poker_tournament_entry[city]'][value='']")
    end

    test "a failed lookup leaves the form untouched instead of erroring", %{conn: conn} do
      Req.Test.stub(HighSociety.Tournaments.Zippopotamus, fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      {:ok, view, _html} = live(conn, ~p"/tournament")

      html =
        view
        |> element("input[name='poker_tournament_entry[zip_code]']")
        |> render_blur(%{"value" => "00000"})

      refute html =~ "King Of Prussia"
      assert has_element?(view, "#tournament_form")
    end

    test "can be submitted together with a valid Ethereum address", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tournament")

      html =
        view
        |> form("#tournament_form", %{
          "poker_tournament_entry" => %{
            "ethereum_address" => "0x" <> String.duplicate("a", 40),
            "first_name" => "Jane",
            "last_name" => "Doe",
            "address" => "123 Main St",
            "city" => "Philadelphia",
            "state" => "PA",
            "zip_code" => "19102",
            "date_of_birth" => "1990-01-15"
          }
        })
        |> render_submit()

      assert html =~ "You&#39;re registered."
    end

    test "an under-18 date of birth re-renders with an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tournament")

      too_young = Date.utc_today() |> Date.add(-365 * 10) |> Date.to_iso8601()

      html =
        view
        |> form("#tournament_form", %{
          "poker_tournament_entry" => %{"date_of_birth" => too_young}
        })
        |> render_submit()

      assert html =~ "must be at least 18 years old"
    end
  end

  describe "/tournament/:id/register" do
    test "reachable for a specific tournament even after it has finished", %{
      conn: conn,
      tournament: tournament
    } do
      HighSociety.Repo.update_all(
        HighSociety.Tournaments.PokerTournament,
        set: [status: "finished"]
      )

      {:ok, _view, html} = live(conn, ~p"/tournament/#{tournament.id}/register")

      assert html =~ tournament.name
      assert html =~ "tournament_form"
    end

    test "a winner returning after the tournament finished can still update KYC info", %{
      conn: conn,
      tournament: tournament
    } do
      {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/register")

      view
      |> form("#tournament_form", %{"poker_tournament_entry" => %{"first_name" => "Jane"}})
      |> render_submit()

      HighSociety.Repo.update_all(
        HighSociety.Tournaments.PokerTournament,
        set: [status: "finished"]
      )

      {:ok, view, html} = live(conn, ~p"/tournament/#{tournament.id}/register")
      assert html =~ "You&#39;re registered."

      html =
        view
        |> form("#tournament_form", %{"poker_tournament_entry" => %{"last_name" => "Doe"}})
        |> render_submit()

      assert html =~ "You&#39;re registered."
    end
  end
end
