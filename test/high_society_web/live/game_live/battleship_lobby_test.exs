defmodule HighSocietyWeb.GameLive.BattleshipLobbyTest do
  # Creating/joining a match spawns a `BattleshipMatch` GenServer that
  # persists through a different process than the test's own - needs the
  # shared sandbox connection `async: false` grants, exactly like
  # `PokerTableLiveTest`.
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts
  alias HighSociety.BattleshipFixtures
  alias HighSociety.Games.BattleshipMatch

  setup :register_and_log_in_user

  test "redirects to log in when not authenticated" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/battleship/lobby")
  end

  test "shows an empty state with no open matches", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby")
    assert render(view) =~ "No open matches"
  end

  test "claiming the one-time chips credits the balance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby")

    assert render(element(view, "#balance")) =~ "$0"
    view |> element("#claim-chips-button") |> render_click()

    refute has_element?(view, "#claim-chips-button")
    assert render(element(view, "#balance")) =~ "$10,000"
  end

  test "creating a match debits the wager and navigates into it", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_balance(user, 1000)
    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby")

    view |> element("form[phx-submit='create_match']") |> render_submit(%{"wager" => "100"})

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r"^/games/battleship/lobby/\w+$"
    assert Accounts.get_user!(user.id).balance == 900
  end

  test "rejects creating a match without enough balance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby")
    view |> element("form[phx-submit='create_match']") |> render_submit(%{"wager" => "100"})
    assert render(view) =~ "don&#39;t have enough balance"
  end

  test "lists an open match created by another user and live-updates as it fills", %{conn: conn} do
    creator = BattleshipFixtures.funded_user()
    slug = BattleshipFixtures.create_match_for_test!(creator, 100)

    {:ok, view, _html} = live(conn, ~p"/games/battleship/lobby")
    assert has_element?(view, "#battleship-match-#{slug}", "Waiting for an opponent")

    joiner = BattleshipFixtures.funded_user()
    {:ok, _view} = BattleshipMatch.join(slug, joiner)

    assert render(view) =~ "Placing fleets"
  end
end
