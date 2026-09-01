defmodule HighSocietyWeb.GameLive.BattleshipMatchTest do
  # Creating/joining/playing a match spawns a `BattleshipMatch` GenServer
  # that persists through a different process than the test's own - needs
  # the shared sandbox connection `async: false` grants, exactly like
  # `PokerTableLiveTest`.
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts
  alias HighSociety.BattleshipFixtures
  alias HighSociety.Games.BattleshipMatch

  setup :register_and_log_in_user

  test "redirects to log in when not authenticated" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/battleship/lobby/nope")
  end

  test "redirects to the lobby for a match that doesn't exist", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/games/battleship/lobby"}}} =
             live(conn, ~p"/games/battleship/lobby/nope")
  end

  test "the creator sees a waiting screen with no join button", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_balance(user, 1000)
    slug = BattleshipFixtures.create_match_for_test!(user, 100)

    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby/#{slug}")

    assert render(view) =~ "Waiting for an opponent"
    refute has_element?(view, "button", "Join this match")
    assert has_element?(view, "button", "Cancel match")
  end

  test "the creator can cancel a waiting match and gets refunded", %{conn: conn, user: user} do
    {:ok, user} = Accounts.adjust_balance(user, 1000)
    slug = BattleshipFixtures.create_match_for_test!(user, 100)

    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby/#{slug}")

    view |> element("button", "Cancel match") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path == ~p"/games/battleship/lobby"
    assert Accounts.get_user!(user.id).balance == 1000
  end

  test "a spectator watching a match gets redirected when the creator cancels it", %{
    conn: conn,
    user: _user
  } do
    creator = BattleshipFixtures.funded_user()
    slug = BattleshipFixtures.create_match_for_test!(creator, 100)

    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby/#{slug}")
    refute has_element?(view, "button", "Cancel match")

    {:ok, _view} = BattleshipMatch.cancel(slug, creator.id)

    assert_redirect(view, "/games/battleship/lobby")
  end

  test "a second visitor can join, debiting their wager", %{conn: _conn} do
    creator = BattleshipFixtures.funded_user()
    slug = BattleshipFixtures.create_match_for_test!(creator, 100)

    joiner = BattleshipFixtures.funded_user()
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(joiner)
    {:ok, view2, _html} = live(conn2, ~p"/games/battleship/lobby/#{slug}")

    view2 |> element("button", "Join this match") |> render_click()

    assert has_element?(view2, "h2", "Place your fleet")
    assert Accounts.get_user!(joiner.id).balance == 10_000 - 100
  end

  test "clearing placement empties the board so ships can be re-placed", %{conn: _conn} do
    creator = BattleshipFixtures.funded_user()
    slug = BattleshipFixtures.create_match_for_test!(creator, 100)
    joiner = BattleshipFixtures.funded_user()
    {:ok, _view} = BattleshipMatch.join(slug, joiner)

    conn = Phoenix.ConnTest.build_conn() |> log_in_user(creator)
    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby/#{slug}")

    view |> element("button", "Randomize") |> render_click()
    assert has_element?(view, "button[phx-value-type='carrier'][disabled]")

    view |> element("button", "Clear all") |> render_click()
    refute has_element?(view, "button[phx-value-type='carrier'][disabled]")
  end

  test "placing ships, readying up, and firing plays through between both seats", %{
    conn: conn,
    user: creator
  } do
    {:ok, creator} = Accounts.adjust_balance(creator, 1000)
    slug = BattleshipFixtures.create_match_for_test!(creator, 100)

    joiner = BattleshipFixtures.funded_user()
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(joiner)

    {:ok, view1, _html} = live(conn, ~p"/games/battleship/lobby/#{slug}")
    {:ok, view2, _html} = live(conn2, ~p"/games/battleship/lobby/#{slug}")

    view2 |> element("button", "Join this match") |> render_click()

    # The join broadcast should reach the creator's own already-mounted view.
    assert render(view1) =~ "Place your fleet"

    view1 |> element("button", "Randomize") |> render_click()
    view1 |> element("button", "Ready") |> render_click()

    view2 |> element("button", "Randomize") |> render_click()
    view2 |> element("button", "Ready") |> render_click()

    # Once both are ready, exactly one of the two boards is now the active
    # firer - fire from whichever view shows an enabled enemy-board cell.
    firer_view =
      if has_element?(view1, "#enemy-board-A1:not([disabled])"), do: view1, else: view2

    html = firer_view |> element("#enemy-board-A1") |> render_click()
    assert html =~ "fired at A1"

    assert_push_event(firer_view, "play_sound", %{sound: "artillery-shot"})
    assert_push_event(firer_view, "play_sound", %{sound: sound})
    assert sound in ["direct-hit", "water-splash"]
  end

  test "forfeiting pays the other seat the full pot and ends the match", %{
    conn: conn,
    user: creator
  } do
    {:ok, creator} = Accounts.adjust_balance(creator, 1000)
    slug = BattleshipFixtures.create_match_for_test!(creator, 100)

    joiner = BattleshipFixtures.funded_user()
    {:ok, _view} = BattleshipMatch.join(slug, joiner)
    BattleshipFixtures.ready_with_random_fleet!(slug, creator.id)
    BattleshipFixtures.ready_with_random_fleet!(slug, joiner.id)

    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby/#{slug}")
    creator_balance_before = Accounts.get_user!(creator.id).balance

    view |> element("button", "Forfeit match") |> render_click()

    assert Accounts.get_user!(joiner.id).balance == 10_000 - 100 + 200
    assert Accounts.get_user!(creator.id).balance == creator_balance_before
  end
end
