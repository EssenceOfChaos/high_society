defmodule HighSocietyWeb.GameLive.BattleshipTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts

  setup :register_and_log_in_user

  test "redirects to log in when not authenticated" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/battleship")
  end

  test "shows a wager picker with no active game", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/battleship")
    assert has_element?(view, "form[phx-submit='start_game']")
  end

  test "claiming the one-time chips credits the balance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/battleship")

    assert render(element(view, "#balance")) =~ "$0"
    view |> element("#claim-chips-button") |> render_click()

    refute has_element?(view, "#claim-chips-button")
    assert render(element(view, "#balance")) =~ "$10,000"
  end

  test "starting a game debits the wager and shows the placement screen", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_balance(user, 1000)
    {:ok, view, _html} = live(conn, ~p"/games/battleship")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "100"})

    assert has_element?(view, "h2", "Place your fleet")
    assert render(element(view, "#balance")) =~ "$900"
  end

  test "randomizing and readying up starts the battle", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_balance(user, 1000)
    {:ok, view, _html} = live(conn, ~p"/games/battleship")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "100"})
    view |> element("button", "Randomize") |> render_click()
    view |> element("button", "Ready") |> render_click()

    assert has_element?(view, "#my-board")
    assert has_element?(view, "#enemy-board")

    # Ships render as bow/hull/stern SVG segments, not a flat color block.
    html = render(view)
    assert html =~ "M64,8 L24,8"
    assert html =~ "M0,8 L48,8"
  end

  test "the computer's unsunk ships are never sent to the client", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_balance(user, 1000)
    {:ok, view, _html} = live(conn, ~p"/games/battleship")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "100"})
    view |> element("button", "Randomize") |> render_click()
    view |> element("button", "Ready") |> render_click()

    # No shots have landed yet, so none of the computer's ships are sunk -
    # the unsunk-ship hull color ("#778da9", see battleship_components.ex)
    # must not appear anywhere under #enemy-board. It legitimately appears
    # under #my-board, which proves this isn't a vacuous assertion (e.g.
    # broken color/selector).
    my_board_html = view |> element("#my-board") |> render()
    enemy_board_html = view |> element("#enemy-board") |> render()

    assert my_board_html =~ "#778da9"
    refute enemy_board_html =~ "#778da9"
  end

  test "clearing placement empties the board so ships can be re-placed", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_balance(user, 1000)
    {:ok, view, _html} = live(conn, ~p"/games/battleship")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "100"})
    view |> element("button", "Randomize") |> render_click()

    # A placed ship disables its own selector button.
    assert has_element?(view, "button[phx-value-type='carrier'][disabled]")

    view |> element("button", "Clear all") |> render_click()

    refute has_element?(view, "button[phx-value-type='carrier'][disabled]")
    assert has_element?(view, "button", "Ready") and has_element?(view, "button[disabled]", "Ready")
  end

  test "firing at the computer's board resolves a shot", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_balance(user, 1000)
    {:ok, view, _html} = live(conn, ~p"/games/battleship")

    view |> element("form[phx-submit='start_game']") |> render_submit(%{"wager" => "100"})
    view |> element("button", "Randomize") |> render_click()
    view |> element("button", "Ready") |> render_click()

    # Fire until either the game ends or we've clearly resolved at least
    # one shot - whichever seat's turn it is, one of these clicks (on the
    # enemy board, when it's the player's turn) will land.
    html =
      Enum.reduce_while(["A1", "B1", "C1", "D1", "E1", "F1", "G1", "H1", "I1", "J1"], nil, fn coord, _ ->
        if has_element?(view, "#enemy-board-#{coord}:not([disabled])") do
          html = view |> element("#enemy-board-#{coord}") |> render_click()
          {:halt, html}
        else
          {:cont, nil}
        end
      end)

    assert html =~ "You:" or html =~ "won" or html =~ "sank"
    assert_push_event(view, "play_sound", %{sound: "artillery-shot"})
    assert_push_event(view, "play_sound", %{sound: sound})
    assert sound in ["direct-hit", "water-splash"]
  end
end
