defmodule HighSocietyWeb.GameLive.BlackjackTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts
  alias HighSociety.Games
  alias HighSociety.Games.Blackjack

  setup :register_and_log_in_user

  test "redirects to log in when not authenticated", %{conn: _conn} do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/blackjack")
  end

  test "shows the claim button pre-claim, and the updated balance post-claim", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    assert render(element(view, "#balance")) =~ "$0"
    assert has_element?(view, "#claim-chips-button")

    view |> element("#claim-chips-button") |> render_click()

    refute has_element?(view, "#claim-chips-button")
    assert render(element(view, "#balance")) =~ "$25,000"
  end

  test "chip buttons build up a pending bet, clamped at the $500 max", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    view |> element("#chip-0-100") |> render_click()
    assert render(element(view, "#bet-amount-0")) =~ "$100"

    for _ <- 1..5, do: view |> element("#chip-0-100") |> render_click()

    # 6 clicks of $100 would be $600, clamped down to the $500 max
    assert render(element(view, "#bet-amount-0")) =~ "$500"

    view |> element("#clear-bet-0") |> render_click()
    assert render(element(view, "#bet-amount-0")) =~ "$0"
    refute has_element?(view, "#clear-bet-0")
  end

  test "second hand starts hidden, can be added, and closing it clears its bet", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    refute has_element?(view, "#betting-box-1")
    assert has_element?(view, "#add-second-hand-button")

    view |> element("#add-second-hand-button") |> render_click()

    assert has_element?(view, "#betting-box-1")
    refute has_element?(view, "#add-second-hand-button")

    view |> element("#chip-1-100") |> render_click()
    assert render(element(view, "#bet-amount-1")) =~ "$100"

    view |> element("#remove-second-hand-button") |> render_click()

    refute has_element?(view, "#betting-box-1")
    assert has_element?(view, "#add-second-hand-button")

    view |> element("#add-second-hand-button") |> render_click()
    assert render(element(view, "#bet-amount-1")) =~ "$0"
  end

  test "dealing with no claimed balance shows an inline error and creates no round", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    view |> element("#chip-0-25") |> render_click()
    html = view |> element("#deal-button") |> render_click()

    assert html =~ "don&#39;t have enough chips"
    assert Games.get_active_blackjack_game(scope) == nil
  end

  test "a bet over the $500 max is rejected server-side even bypassing the UI clamp", %{
    scope: scope
  } do
    {:ok, _user} = Accounts.claim_starting_chips(scope.user)
    scope = %{scope | user: Accounts.get_user!(scope.user.id)}

    assert {:error, :bet_too_large} = Games.start_blackjack_round(scope, %{0 => 9999})
    assert Games.get_active_blackjack_game(scope) == nil
  end

  test "a full round: place a bet, deal, hit/stand to conclusion, and balance updates", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    view |> element("#claim-chips-button") |> render_click()

    view |> element("#chip-0-25") |> render_click()
    html = view |> element("#deal-button") |> render_click()

    assert html =~ "Dealer"
    assert has_element?(view, "#hand-box-0")
    refute has_element?(view, "#betting-area")

    html =
      Enum.reduce_while(1..200, html, fn _, _ ->
        cond do
          has_element?(view, "#new-round-button") ->
            {:halt, render(view)}

          has_element?(view, "#stand-button-0") ->
            {:cont, view |> element("#stand-button-0") |> render_click()}

          true ->
            # The dealer is playing out one paced step at a time (see
            # HighSocietyWeb.GameLive.Blackjack) - give the scheduled
            # :dealer_step message time to arrive.
            Process.sleep(5)
            {:cont, render(view)}
        end
      end)

    assert html =~ "New round"

    updated_user = Accounts.get_user!(scope.user.id)
    game = Games.get_active_blackjack_game(scope)
    assert game.status == "round_over"

    total_payout = game.hands |> Enum.map(& &1["payout"]) |> Enum.sum()
    assert updated_user.balance == Accounts.starting_chip_amount() - 25 + total_payout
  end

  test "a dealer natural blackjack ends the round immediately, before any player action", %{
    conn: conn,
    scope: scope
  } do
    {:ok, user} = Accounts.claim_starting_chips(scope.user)
    scope = %{scope | user: user}

    # keep dealing real (randomly shuffled) rounds until the dealer itself
    # is dealt a natural - exercises the actual `Blackjack.new/1` peek
    # logic rather than rigging a persisted round to fake the outcome
    game =
      Stream.repeatedly(fn ->
        {:ok, game} = Games.start_blackjack_round(scope, %{0 => 25})
        game
      end)
      |> Enum.find(&Blackjack.blackjack?(&1.dealer_hand))

    assert game.status == "round_over"

    {:ok, view, html} = live(conn, ~p"/games/blackjack")

    assert html =~ "New round"
    refute has_element?(view, "#betting-area")
    refute has_element?(view, "#hit-button-0")
    refute has_element?(view, "#double-button-0")
    refute has_element?(view, "#split-button-0")
  end

  test "double down doubles the bet, draws exactly one card, and ends the hand's turn", %{
    conn: conn,
    scope: scope
  } do
    {:ok, user} = Accounts.claim_starting_chips(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 25})

    # rig a plain 2-card active hand deterministically - the random deal
    # would otherwise only sometimes land a hand eligible to double down
    game
    |> Games.BlackjackGame.changeset(%{
      status: "player_turn",
      shoe: ["2S"],
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 25,
          "cards" => ["6H", "5D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: 0,
      # already stands on its own (>= 17), so the paced dealer step that
      # follows the double down doesn't need to draw from the (deliberately
      # tiny) shoe above
      dealer_hand: ["10H", "7D"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    assert has_element?(view, "#double-button-0")
    html = view |> element("#double-button-0") |> render_click()

    assert html =~ "(doubled)"
    refute has_element?(view, "#double-button-0")
    refute has_element?(view, "#hit-button-0")

    updated_game = Games.get_active_blackjack_game(scope)
    hand = hd(updated_game.hands)
    assert hand["cards"] == ["6H", "5D", "2S"]
    assert hand["bet"] == 50
    assert hand["doubled"] == true

    assert Accounts.get_user!(user.id).balance == Accounts.starting_chip_amount() - 25 - 25
  end

  test "splitting a pair plays out as two independent hands", %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_starting_chips(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 25})

    # rig a splittable pair deterministically - the random deal would
    # otherwise only rarely land a same-value pair
    game
    |> Games.BlackjackGame.changeset(%{
      status: "player_turn",
      shoe: ["2S", "3H"],
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 25,
          "cards" => ["8H", "8D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: 0,
      dealer_hand: ["7H", "7D"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    assert has_element?(view, "#split-button-0")
    html = view |> element("#split-button-0") |> render_click()

    assert html =~ "Hand 1A"
    assert html =~ "Hand 1B"
    refute has_element?(view, "#split-button-0")

    assert Accounts.get_user!(user.id).balance == Accounts.starting_chip_amount() - 25 - 25

    updated_game = Games.get_active_blackjack_game(scope)
    assert length(updated_game.hands) == 2
    assert Enum.map(updated_game.hands, & &1["bet"]) == [25, 25]

    # play the first split hand out, then the second becomes active
    view |> element("#stand-button-0") |> render_click()
    assert has_element?(view, "#stand-button-1")
  end

  test "New round returns to the betting UI without touching the persisted round", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    view |> element("#claim-chips-button") |> render_click()
    view |> element("#chip-0-25") |> render_click()
    view |> element("#deal-button") |> render_click()

    Enum.reduce_while(1..200, nil, fn _, _ ->
      cond do
        has_element?(view, "#new-round-button") ->
          {:halt, nil}

        has_element?(view, "#stand-button-0") ->
          view |> element("#stand-button-0") |> render_click()
          {:cont, nil}

        true ->
          Process.sleep(5)
          {:cont, nil}
      end
    end)

    game_before = Games.get_active_blackjack_game(scope)
    html = view |> element("#new-round-button") |> render_click()

    assert has_element?(view, "#betting-area")
    assert html =~ "Deal"
    assert Games.get_active_blackjack_game(scope).id == game_before.id
    assert Games.get_active_blackjack_game(scope).status == game_before.status
  end
end
