defmodule HighSocietyWeb.GameLive.PokerTableLiveTest do
  # Poker tables are long-lived, application-wide GenServers rather than
  # per-test state - see `HighSociety.PokerFixtures`.
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts
  alias HighSociety.PokerFixtures

  @slug "new-york"

  setup :register_and_log_in_user

  setup do
    PokerFixtures.reset_table_around_test!(@slug)
    :ok
  end

  test "redirects to log in when not authenticated" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/poker/#{@slug}")
  end

  test "redirects to the lobby for an unknown table", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/games/poker"}}} = live(conn, ~p"/games/poker/nope")
  end

  test "shows an empty table with a join button on every seat", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    assert has_element?(view, "#seat-0 button", "Join")
    assert has_element?(view, "#seat-7 button", "Join")
  end

  test "claiming the one-time poker chips credits the balance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    assert render(element(view, "#balance")) =~ "$0"
    view |> element("#claim-poker-chips-button") |> render_click()

    refute has_element?(view, "#claim-poker-chips-button")
    assert render(element(view, "#balance")) =~ "$10,000"
  end

  test "sitting down debits the balance and shows the seated player", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_balance(user, 1000)
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    view |> element("#seat-0 button", "Join") |> render_click()
    assert has_element?(view, "#join-modal")

    view |> element("#buy-in-slider") |> render_change(%{"amount" => "100"})
    view |> element("#join-modal form") |> render_submit()

    refute has_element?(view, "#join-modal")
    assert render(element(view, "#balance")) =~ "$900"

    username = user.email |> String.split("@") |> hd()
    assert has_element?(view, "#seat-0", username)
    assert has_element?(view, "#seat-0", "$100")
    assert has_element?(view, "#leave-table-button")
  end

  test "a full hand plays through preflop, flop, turn, and river to a showdown", %{
    conn: conn,
    user: user1
  } do
    {:ok, _} = Accounts.adjust_balance(user1, 1000)
    {:ok, view1, _html} = live(conn, ~p"/games/poker/#{@slug}")
    view1 |> element("#seat-0 button", "Join") |> render_click()
    view1 |> element("#buy-in-slider") |> render_change(%{"amount" => "100"})
    view1 |> element("#join-modal form") |> render_submit()

    user2 = HighSociety.AccountsFixtures.user_fixture()
    {:ok, _} = Accounts.adjust_balance(user2, 1000)
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(user2)
    {:ok, view2, _html} = live(conn2, ~p"/games/poker/#{@slug}")
    view2 |> element("#seat-1 button", "Join") |> render_click()
    view2 |> element("#buy-in-slider") |> render_change(%{"amount" => "100"})
    view2 |> element("#join-modal form") |> render_submit()

    # heads-up: the button (seat 0, dealt first since it's the very first
    # hand) posts the small blind and acts first preflop
    view1 |> element("#call-button") |> render_click()
    view2 |> element("#check-button") |> render_click()

    assert HighSociety.Games.PokerTable.get_state(@slug).hand.street == :flop
    assert length(HighSociety.Games.PokerTable.get_state(@slug).hand.community_cards) == 3

    # postflop, the seat left of the button (seat 1) acts first
    view2 |> element("#check-button") |> render_click()
    view1 |> element("#check-button") |> render_click()

    assert HighSociety.Games.PokerTable.get_state(@slug).hand.street == :turn
    assert length(HighSociety.Games.PokerTable.get_state(@slug).hand.community_cards) == 4

    view2 |> element("#check-button") |> render_click()
    view1 |> element("#check-button") |> render_click()

    assert HighSociety.Games.PokerTable.get_state(@slug).hand.street == :river
    assert length(HighSociety.Games.PokerTable.get_state(@slug).hand.community_cards) == 5

    view2 |> element("#check-button") |> render_click()
    view1 |> element("#check-button") |> render_click()

    hand = HighSociety.Games.PokerTable.get_state(@slug).hand
    assert hand.status == :hand_over
    assert hand.pots != nil

    banner = view1 |> element("#winner-banner") |> render()
    assert banner =~ "$"

    hand.pots
    |> Enum.flat_map(& &1.winners)
    |> Enum.uniq()
    |> Enum.each(fn seat -> assert banner =~ hand.seats[seat].username end)

    assert has_element?(view1, "#pot-chips")
  end

  test "a player never receives an opponent's hole cards while a hand is in progress", %{
    conn: conn,
    user: user1
  } do
    {:ok, _} = Accounts.adjust_balance(user1, 1000)
    {:ok, view1, _html} = live(conn, ~p"/games/poker/#{@slug}")
    view1 |> element("#seat-0 button", "Join") |> render_click()
    view1 |> element("#buy-in-slider") |> render_change(%{"amount" => "100"})
    view1 |> element("#join-modal form") |> render_submit()

    user2 = HighSociety.AccountsFixtures.user_fixture()
    {:ok, _} = Accounts.adjust_balance(user2, 1000)
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(user2)
    {:ok, view2, _html} = live(conn2, ~p"/games/poker/#{@slug}")
    view2 |> element("#seat-1 button", "Join") |> render_click()
    view2 |> element("#buy-in-slider") |> render_change(%{"amount" => "100"})
    view2 |> element("#join-modal form") |> render_submit()

    hand = HighSociety.Games.PokerTable.get_state(@slug).hand
    assert hand.status == :in_progress

    seat0_cards = hand.seats[0].hole_cards
    seat1_cards = hand.seats[1].hole_cards
    assert length(seat0_cards) == 2
    assert length(seat1_cards) == 2

    html1 = render(view1)
    html2 = render(view2)

    # Each player sees their own hole cards...
    for card <- seat0_cards, do: assert(html1 =~ ~s(alt="#{card}"))
    for card <- seat1_cards, do: assert(html2 =~ ~s(alt="#{card}"))

    # ...but never the raw value of an opponent's face-down cards - the
    # server must omit them from that viewer's render entirely rather than
    # relying on CSS to hide them, since the rendered HTML (and the
    # LiveView diffs sent over the socket) are visible in the browser's
    # Network tab regardless of what's painted on screen.
    for card <- seat1_cards, do: refute(html1 =~ ~s(alt="#{card}"))
    for card <- seat0_cards, do: refute(html2 =~ ~s(alt="#{card}"))
  end

  test "leaving the table cashes the stack back out", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_balance(user, 1000)
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    view |> element("#seat-0 button", "Join") |> render_click()
    view |> element("#buy-in-slider") |> render_change(%{"amount" => "100"})
    view |> element("#join-modal form") |> render_submit()

    view |> element("#leave-table-button") |> render_click()

    refute has_element?(view, "#leave-table-button")
    assert has_element?(view, "#seat-0 button", "Join")
    assert render(element(view, "#balance")) =~ "$1,000"
  end
end
