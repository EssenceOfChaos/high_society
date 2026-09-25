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

  test "claiming the one-time poker tokens credits the balance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    assert render(element(view, "#tokens-balance")) =~ "0 Tokens"
    view |> element("#claim-poker-tokens-button") |> render_click()

    refute has_element?(view, "#claim-poker-tokens-button")
    assert render(element(view, "#tokens-balance")) =~ "500,000 Tokens"
  end

  test "sitting down debits the balance and shows the seated player", %{conn: conn, user: user} do
    {:ok, _user} = Accounts.adjust_tokens_balance(user, 100_000, "test_funding")
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    view |> element("#seat-0 button", "Join") |> render_click()
    assert has_element?(view, "#join-modal")

    view |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view |> element("#join-modal form") |> render_submit()

    refute has_element?(view, "#join-modal")
    assert render(element(view, "#tokens-balance")) =~ "90,000 Tokens"

    username = user.email |> String.split("@") |> hd()
    assert has_element?(view, "#seat-0", username)
    assert has_element?(view, "#seat-0", "10,000")
    assert has_element?(view, "#leave-table-button")
  end

  test "the settings button opens and closes the settings modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    refute has_element?(view, "#settings-modal")
    view |> element("#settings-button") |> render_click()
    assert has_element?(view, "#settings-modal")

    view |> element("#settings-modal button[aria-label='Close']") |> render_click()
    refute has_element?(view, "#settings-modal")
  end

  test "picking a card back persists it and highlights the new choice", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    view |> element("#settings-button") |> render_click()
    view |> element("#card-back-blue") |> render_click()

    assert Accounts.get_user!(user.id).card_back == "blue"
    assert render(element(view, "#card-back-blue")) =~ "border-primary"
  end

  test "picking a felt color persists it and applies it to the felt", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    view |> element("#settings-button") |> render_click()
    view |> element("#felt-color-red") |> render_click()

    assert Accounts.get_user!(user.id).felt_color == "red"
    assert render(element(view, "#poker-felt")) =~ "from-red-900"
  end

  test "toggling a muck preference on and back off", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    view |> element("#settings-button") |> render_click()
    view |> element("#muck-always-button") |> render_click()
    assert Accounts.get_user!(user.id).muck_preference == "always"

    view |> element("#muck-never-button") |> render_click()
    assert Accounts.get_user!(user.id).muck_preference == "never"

    view |> element("#muck-never-button") |> render_click()
    assert Accounts.get_user!(user.id).muck_preference == nil
  end

  test "a full hand plays through preflop, flop, turn, and river to a showdown", %{
    conn: conn,
    user: user1
  } do
    {:ok, _} = Accounts.adjust_tokens_balance(user1, 100_000, "test_funding")
    {:ok, view1, _html} = live(conn, ~p"/games/poker/#{@slug}")
    view1 |> element("#seat-0 button", "Join") |> render_click()
    view1 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view1 |> element("#join-modal form") |> render_submit()

    user2 = HighSociety.AccountsFixtures.user_fixture()
    {:ok, _} = Accounts.adjust_tokens_balance(user2, 100_000, "test_funding")
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(user2)
    {:ok, view2, _html} = live(conn2, ~p"/games/poker/#{@slug}")
    view2 |> element("#seat-1 button", "Join") |> render_click()
    view2 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
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
    assert banner =~ "Tokens"

    hand.pots
    |> Enum.flat_map(& &1.winners)
    |> Enum.uniq()
    |> Enum.each(fn seat -> assert banner =~ hand.seats[seat].username end)

    assert has_element?(view1, "#pot-chips")
  end

  test "each seat's last action this street is badged, and clears on the next street", %{
    conn: conn,
    user: user1
  } do
    {:ok, _} = Accounts.adjust_tokens_balance(user1, 100_000, "test_funding")
    {:ok, view1, _html} = live(conn, ~p"/games/poker/#{@slug}")
    view1 |> element("#seat-0 button", "Join") |> render_click()
    view1 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view1 |> element("#join-modal form") |> render_submit()

    user2 = HighSociety.AccountsFixtures.user_fixture()
    {:ok, _} = Accounts.adjust_tokens_balance(user2, 100_000, "test_funding")
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(user2)
    {:ok, view2, _html} = live(conn2, ~p"/games/poker/#{@slug}")
    view2 |> element("#seat-1 button", "Join") |> render_click()
    view2 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view2 |> element("#join-modal form") |> render_submit()

    refute has_element?(view1, "#seat-0", "Called")
    refute has_element?(view1, "#seat-1", "Checked")

    # heads-up: seat 0 (the button) posts the small blind and calls first
    view1 |> element("#call-button") |> render_click()
    assert has_element?(view1, "#seat-0", "Called")
    assert has_element?(view2, "#seat-0", "Called")

    view2 |> element("#check-button") |> render_click()

    assert HighSociety.Games.PokerTable.get_state(@slug).hand.street == :flop

    # the flop closes preflop's betting - both badges are stale now
    refute has_element?(view1, "#seat-0", "Called")
    refute has_element?(view1, "#seat-1", "Checked")

    # postflop, seat 1 acts first - seat 0 hasn't responded yet, so the
    # badge is still live (unlike the heads-up call above, which closes
    # the street in the very same action and wipes it again immediately)
    view2 |> form("#action-bar form") |> render_submit()
    assert has_element?(view1, "#seat-1", "Bet")
  end

  test "quick-bet buttons offer 1/3, 2/3, and full pot sizings, at least the big blind", %{
    conn: conn,
    user: user1
  } do
    {:ok, _} = Accounts.adjust_tokens_balance(user1, 100_000, "test_funding")
    {:ok, view1, _html} = live(conn, ~p"/games/poker/#{@slug}")
    view1 |> element("#seat-0 button", "Join") |> render_click()
    view1 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view1 |> element("#join-modal form") |> render_submit()

    user2 = HighSociety.AccountsFixtures.user_fixture()
    {:ok, _} = Accounts.adjust_tokens_balance(user2, 100_000, "test_funding")
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(user2)
    {:ok, view2, _html} = live(conn2, ~p"/games/poker/#{@slug}")
    view2 |> element("#seat-1 button", "Join") |> render_click()
    view2 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view2 |> element("#join-modal form") |> render_submit()

    # Preflop, the big blind already sets `current_bet` (this is sizing a
    # raise, not an opening bet), so play it out to the flop instead -
    # current_bet resets to 0 there, and the pot is a clean 400 (100 SB +
    # 200 BB, then seat 0 calling the extra 100 to match).
    view1 |> element("#call-button") |> render_click()
    view2 |> element("#check-button") |> render_click()
    assert HighSociety.Games.PokerTable.get_state(@slug).hand.street == :flop

    # 1/3 of 400 (133) is below the 200 big blind and doesn't show; 2/3
    # (267) and the full pot (400) both do.
    html = render(view2)
    refute html =~ "quick-bet-third"
    assert has_element?(view2, "#quick-bet-two-thirds", "267")
    assert has_element?(view2, "#quick-bet-pot", "400")

    view2 |> element("#quick-bet-pot") |> render_click()

    hand = HighSociety.Games.PokerTable.get_state(@slug).hand
    assert hand.seats[1].contributed_this_street == 400
    assert hand.current_bet == 400
  end

  test "a genuine showdown reveals the winner's cards automatically, with no reveal button", %{
    conn: conn,
    user: user1
  } do
    {:ok, _} = Accounts.adjust_tokens_balance(user1, 100_000, "test_funding")
    {:ok, view1, _html} = live(conn, ~p"/games/poker/#{@slug}")
    view1 |> element("#seat-0 button", "Join") |> render_click()
    view1 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view1 |> element("#join-modal form") |> render_submit()

    user2 = HighSociety.AccountsFixtures.user_fixture()
    {:ok, _} = Accounts.adjust_tokens_balance(user2, 100_000, "test_funding")
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(user2)
    {:ok, view2, _html} = live(conn2, ~p"/games/poker/#{@slug}")
    view2 |> element("#seat-1 button", "Join") |> render_click()
    view2 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view2 |> element("#join-modal form") |> render_submit()

    view1 |> element("#call-button") |> render_click()
    view2 |> element("#check-button") |> render_click()
    view2 |> element("#check-button") |> render_click()
    view1 |> element("#check-button") |> render_click()
    view2 |> element("#check-button") |> render_click()
    view1 |> element("#check-button") |> render_click()
    view2 |> element("#check-button") |> render_click()
    view1 |> element("#check-button") |> render_click()

    hand = HighSociety.Games.PokerTable.get_state(@slug).hand
    assert hand.status == :hand_over
    winning_seats = hand.pots |> Enum.flat_map(& &1.winners) |> Enum.uniq()
    [winning_seat | _] = winning_seats

    winner_cards = hand.seats[winning_seat].hole_cards
    {winner_view, other_view} = if winning_seat == 0, do: {view1, view2}, else: {view2, view1}

    # A genuine showdown force-reveals every pot's winner the instant the
    # hand ends - nobody folded, so the winner has to prove they actually
    # had the best hand rather than being able to muck. No click required,
    # and no reveal button is offered since there's nothing left to reveal.
    for card <- winner_cards, do: assert(render(winner_view) =~ ~s(alt="#{card}"))
    for card <- winner_cards, do: assert(render(other_view) =~ ~s(alt="#{card}"))
    refute has_element?(winner_view, "#reveal-hand-button-#{winning_seat}")
  end

  test "'never muck' auto-reveals an uncontested win with no button needed", %{
    conn: conn,
    user: user1
  } do
    {:ok, _} = Accounts.adjust_tokens_balance(user1, 100_000, "test_funding")
    {:ok, view1, _html} = live(conn, ~p"/games/poker/#{@slug}")
    view1 |> element("#seat-0 button", "Join") |> render_click()
    view1 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view1 |> element("#join-modal form") |> render_submit()

    user2 = HighSociety.AccountsFixtures.user_fixture()
    {:ok, user2} = Accounts.adjust_tokens_balance(user2, 100_000, "test_funding")
    {:ok, user2} = Accounts.update_poker_settings(user2, %{muck_preference: "never"})
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(user2)
    {:ok, view2, _html} = live(conn2, ~p"/games/poker/#{@slug}")
    view2 |> element("#seat-1 button", "Join") |> render_click()
    view2 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view2 |> element("#join-modal form") |> render_submit()

    # Heads-up, the button (seat 0) posts the small blind and acts first
    # preflop - folding it immediately gives seat 1 (user2, "never muck") an
    # uncontested win with no showdown.
    view1 |> element("#fold-button") |> render_click()

    hand = HighSociety.Games.PokerTable.get_state(@slug).hand
    assert hand.status == :hand_over
    winner_cards = hand.seats[1].hole_cards

    refute has_element?(view2, "#reveal-hand-button-1")
    for card <- winner_cards, do: assert(render(view1) =~ ~s(alt="#{card}"))
  end

  test "'always muck' hides the reveal button on an uncontested win", %{
    conn: conn,
    user: user1
  } do
    {:ok, _} = Accounts.adjust_tokens_balance(user1, 100_000, "test_funding")
    {:ok, _} = Accounts.update_poker_settings(user1, %{muck_preference: "always"})
    {:ok, view1, _html} = live(conn, ~p"/games/poker/#{@slug}")
    view1 |> element("#seat-0 button", "Join") |> render_click()
    view1 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view1 |> element("#join-modal form") |> render_submit()

    user2 = HighSociety.AccountsFixtures.user_fixture()
    {:ok, _} = Accounts.adjust_tokens_balance(user2, 100_000, "test_funding")
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(user2)
    {:ok, view2, _html} = live(conn2, ~p"/games/poker/#{@slug}")
    view2 |> element("#seat-1 button", "Join") |> render_click()
    view2 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view2 |> element("#join-modal form") |> render_submit()

    # Heads-up, seat 0 (the button) acts first preflop - it calls, then
    # seat 1 (user2) folds instead of calling back, leaving seat 0
    # (user1, "always muck") an uncontested winner with the button offer
    # suppressed.
    view1 |> element("#call-button") |> render_click()
    view2 |> element("#fold-button") |> render_click()

    hand = HighSociety.Games.PokerTable.get_state(@slug).hand
    assert hand.status == :hand_over
    winner_cards = hand.seats[0].hole_cards

    refute has_element?(view1, "#reveal-hand-button-0")
    for card <- winner_cards, do: refute(render(view2) =~ ~s(alt="#{card}"))
  end

  test "a player never receives an opponent's hole cards while a hand is in progress", %{
    conn: conn,
    user: user1
  } do
    {:ok, _} = Accounts.adjust_tokens_balance(user1, 100_000, "test_funding")
    {:ok, view1, _html} = live(conn, ~p"/games/poker/#{@slug}")
    view1 |> element("#seat-0 button", "Join") |> render_click()
    view1 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view1 |> element("#join-modal form") |> render_submit()

    user2 = HighSociety.AccountsFixtures.user_fixture()
    {:ok, _} = Accounts.adjust_tokens_balance(user2, 100_000, "test_funding")
    conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(user2)
    {:ok, view2, _html} = live(conn2, ~p"/games/poker/#{@slug}")
    view2 |> element("#seat-1 button", "Join") |> render_click()
    view2 |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
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
    {:ok, _user} = Accounts.adjust_tokens_balance(user, 100_000, "test_funding")
    {:ok, view, _html} = live(conn, ~p"/games/poker/#{@slug}")

    view |> element("#seat-0 button", "Join") |> render_click()
    view |> element("#buy-in-slider") |> render_change(%{"amount" => "10000"})
    view |> element("#join-modal form") |> render_submit()

    view |> element("#leave-table-button") |> render_click()

    refute has_element?(view, "#leave-table-button")
    assert has_element?(view, "#seat-0 button", "Join")
    assert render(element(view, "#tokens-balance")) =~ "100,000 Tokens"
  end
end
