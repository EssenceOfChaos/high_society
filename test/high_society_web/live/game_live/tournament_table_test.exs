defmodule HighSocietyWeb.GameLive.TournamentTableTest do
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures

  alias HighSociety.Accounts
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

  test "an uncontested win (everyone else folds) keeps the winner's cards hidden from the table until they choose to reveal them",
       %{conn: conn, user: user} do
    other_user = user_fixture()
    tournament = tournament_fixture()
    tournament = start_tournament_for_test!(tournament, [user, other_user])
    [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)

    view_state = HighSociety.Games.TournamentTable.get_state(slug)
    folding_seat = view_state.hand.action_on
    folding_user_id = view_state.hand.seats[folding_seat].user_id

    folding_conn =
      if folding_user_id == user.id,
        do: conn,
        else: log_in_user(Phoenix.ConnTest.build_conn(), other_user)

    winning_conn =
      if folding_user_id == user.id,
        do: log_in_user(Phoenix.ConnTest.build_conn(), other_user),
        else: conn

    {:ok, folder_view, _html} =
      live(folding_conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")

    {:ok, winner_view, _html} =
      live(winning_conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")

    folder_view |> element("#fold-button") |> render_click()

    updated = HighSociety.Games.TournamentTable.get_state(slug)
    assert updated.hand.status == :hand_over
    winning_seat = Enum.find(updated.hand.seats, fn {i, _s} -> i != folding_seat end)
    {winning_seat_index, winning_hand_seat} = winning_seat

    # The loser's own view is the sensitive one: they mustn't see the
    # winner's (possibly bluffed) hand just because nobody called it.
    for card <- winning_hand_seat.hole_cards do
      refute render(folder_view) =~ ~s(alt="#{card}")
    end

    # But the winner can still choose to show it off.
    assert has_element?(winner_view, "#reveal-hand-button-#{winning_seat_index}")
    winner_view |> element("#reveal-hand-button-#{winning_seat_index}") |> render_click()

    for card <- winning_hand_seat.hole_cards do
      assert render(folder_view) =~ ~s(alt="#{card}")
    end

    refute has_element?(winner_view, "#reveal-hand-button-#{winning_seat_index}")
  end

  test "a genuine showdown still reveals every non-folded hand", %{conn: conn, user: user} do
    other_user = user_fixture()
    tournament = tournament_fixture()
    tournament = start_tournament_for_test!(tournament, [user, other_user])
    [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)

    view_state = HighSociety.Games.TournamentTable.get_state(slug)
    acting_user_id = view_state.hand.seats[view_state.hand.action_on].user_id

    conn1 =
      if acting_user_id == user.id,
        do: conn,
        else: log_in_user(Phoenix.ConnTest.build_conn(), other_user)

    conn2 =
      if acting_user_id == user.id,
        do: log_in_user(Phoenix.ConnTest.build_conn(), other_user),
        else: conn

    {:ok, acting_view, _html} = live(conn1, ~p"/tournament/#{tournament.id}/tables/#{slug}")
    {:ok, other_view, _html} = live(conn2, ~p"/tournament/#{tournament.id}/tables/#{slug}")

    acting_view |> element("#call-button") |> render_click()
    other_view |> element("#check-button") |> render_click()
    other_view |> element("#check-button") |> render_click()
    acting_view |> element("#check-button") |> render_click()
    other_view |> element("#check-button") |> render_click()
    acting_view |> element("#check-button") |> render_click()
    other_view |> element("#check-button") |> render_click()
    acting_view |> element("#check-button") |> render_click()

    updated = HighSociety.Games.TournamentTable.get_state(slug)
    assert updated.hand.status == :hand_over

    for {_i, seat} <- updated.hand.seats, seat.status != :folded, card <- seat.hole_cards do
      assert render(acting_view) =~ ~s(alt="#{card}")
    end

    # Already shown to everyone - there's nothing left to offer a "reveal" for.
    for {seat_index, _seat} <- updated.hand.seats do
      refute has_element?(acting_view, "#reveal-hand-button-#{seat_index}")
    end
  end

  test "the settings button opens and closes the settings modal", %{conn: conn} do
    tournament = tournament_fixture()
    users = for _ <- 1..2, do: user_fixture()
    tournament = start_tournament_for_test!(tournament, users)
    [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)

    {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")

    refute has_element?(view, "#settings-modal")
    view |> element("#settings-button") |> render_click()
    assert has_element?(view, "#settings-modal")

    view |> element("#settings-modal button[aria-label='Close']") |> render_click()
    refute has_element?(view, "#settings-modal")
  end

  test "picking a card back persists it and applies it to opponents' hidden cards", %{
    conn: conn,
    user: user
  } do
    tournament = tournament_fixture()
    other_user = user_fixture()
    tournament = start_tournament_for_test!(tournament, [user, other_user])
    [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)

    {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")

    view |> element("#settings-button") |> render_click()
    view |> element("#card-back-blue") |> render_click()

    assert Accounts.get_user!(user.id).card_back == "blue"
    assert render(view) =~ "card_back_blue.png"
  end

  test "picking a felt color persists it and applies it to the felt", %{conn: conn, user: user} do
    tournament = tournament_fixture()
    other_user = user_fixture()
    tournament = start_tournament_for_test!(tournament, [user, other_user])
    [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)

    {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")

    view |> element("#settings-button") |> render_click()
    view |> element("#felt-color-red") |> render_click()

    assert Accounts.get_user!(user.id).felt_color == "red"
    assert render(element(view, "#tournament-felt")) =~ "from-red-900"
  end

  describe "tournament info modal" do
    test "opens and closes, showing live entrants/remaining/level/blinds", %{conn: conn} do
      tournament = tournament_fixture()
      users = for _ <- 1..3, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)
      [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)

      {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")

      refute has_element?(view, "#tournament-info-modal")
      view |> element("#tournament-info-button") |> render_click()
      assert has_element?(view, "#tournament-info-modal")

      assert render(element(view, "#tournament-info-entrants")) =~ "3"
      assert render(element(view, "#tournament-info-remaining")) =~ "3"
      assert render(element(view, "#tournament-info-level")) =~ "1 of 15"
      assert render(element(view, "#tournament-info-blinds")) =~ "Blinds"

      view |> element("#tournament-info-modal button[aria-label='Close']") |> render_click()
      refute has_element?(view, "#tournament-info-modal")
    end

    test "shows a countdown to the next break when one remains in the schedule", %{conn: conn} do
      tournament = tournament_fixture()
      users = for _ <- 1..2, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)
      [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)

      {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")
      view |> element("#tournament-info-button") |> render_click()

      assert render(view) =~ "Next break in"
      assert has_element?(view, "#tournament-info-break-countdown")
      refute render(view) =~ "No more breaks scheduled"
    end

    test "shows the break-ends countdown while the tournament is on break", %{conn: conn} do
      tournament =
        tournament_fixture(%{
          level_minutes: 12,
          break_every_minutes: 12,
          break_minutes: 5,
          blind_levels: [
            %{"small_blind" => 100, "big_blind" => 200},
            %{"small_blind" => 150, "big_blind" => 300}
          ]
        })

      users = for _ <- 1..2, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)
      pid = GenServer.whereis(TournamentCoordinator.via(tournament.id))
      send(pid, :advance)
      assert TournamentCoordinator.get_state(tournament.id).on_break

      [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)
      {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")
      view |> element("#tournament-info-button") |> render_click()

      assert render(view) =~ "On a break - resumes in"
      assert has_element?(view, "#tournament-info-break-countdown")
    end

    test "shows 'no more breaks scheduled' once every break has already happened", %{conn: conn} do
      tournament =
        tournament_fixture(%{
          level_minutes: 12,
          break_every_minutes: 24,
          break_minutes: 5,
          blind_levels: [
            %{"small_blind" => 100, "big_blind" => 200},
            %{"small_blind" => 150, "big_blind" => 300},
            %{"small_blind" => 200, "big_blind" => 400}
          ]
        })

      users = for _ <- 1..2, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)
      pid = GenServer.whereis(TournamentCoordinator.via(tournament.id))
      # level 1 -> 2, 2 -> break, break -> 3 (the final level; no more breaks)
      send(pid, :advance)
      send(pid, :advance)
      send(pid, :advance)
      assert TournamentCoordinator.get_state(tournament.id).current_level == 3

      [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)
      {:ok, view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables/#{slug}")
      view |> element("#tournament-info-button") |> render_click()

      assert render(view) =~ "No more breaks scheduled"
      refute has_element?(view, "#tournament-info-break-countdown")
    end
  end
end
