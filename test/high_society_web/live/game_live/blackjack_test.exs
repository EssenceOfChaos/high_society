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
          has_element?(view, "#rebet-button") ->
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

    assert html =~ "Rebet"
    assert html =~ "Change bet"

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

    assert html =~ "Rebet"
    assert html =~ "Change bet"
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

  test "Change bet returns to the betting UI without touching the persisted round", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    view |> element("#claim-chips-button") |> render_click()
    view |> element("#chip-0-25") |> render_click()
    view |> element("#deal-button") |> render_click()

    Enum.reduce_while(1..200, nil, fn _, _ ->
      cond do
        has_element?(view, "#change-bet-button") ->
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
    html = view |> element("#change-bet-button") |> render_click()

    assert has_element?(view, "#betting-area")
    assert html =~ "Deal"
    assert Games.get_active_blackjack_game(scope).id == game_before.id
    assert Games.get_active_blackjack_game(scope).status == game_before.status
  end

  test "Rebet immediately re-deals a new round using the same bet, without touching balance twice",
       %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    view |> element("#claim-chips-button") |> render_click()
    view |> element("#chip-0-25") |> render_click()
    view |> element("#deal-button") |> render_click()

    Enum.reduce_while(1..200, nil, fn _, _ ->
      cond do
        has_element?(view, "#rebet-button") ->
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
    balance_before = Accounts.get_user!(scope.user.id).balance

    html = view |> element("#rebet-button") |> render_click()

    assert html =~ "Dealer"
    refute has_element?(view, "#betting-area")

    game_after = Games.get_active_blackjack_game(scope)
    assert game_after.id != game_before.id

    assert game_after.status == "player_turn" or game_after.status == "dealer_turn" or
             game_after.status == "round_over"

    assert Enum.map(game_after.hands, & &1["bet"]) == [25]
    assert Accounts.get_user!(scope.user.id).balance == balance_before - 25
  end

  test "Rebet on a two-box round re-deals both boxes at their original (pre-double) stakes", %{
    conn: conn,
    scope: scope
  } do
    {:ok, user} = Accounts.claim_starting_chips(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 25, 1 => 50})

    # rig a settled two-box round with box 0 doubled, so the recovered
    # rebet stake for box 0 must be halved back to its original 25
    game
    |> Games.BlackjackGame.changeset(%{
      status: "round_over",
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 50,
          "cards" => ["6H", "5D", "2S"],
          "status" => "standing",
          "outcome" => "loss",
          "payout" => 0,
          "doubled" => true
        },
        %{
          "id" => 1,
          "box" => 1,
          "bet" => 50,
          "cards" => ["9H", "9D"],
          "status" => "standing",
          "outcome" => "loss",
          "payout" => 0
        }
      ],
      active_hand: nil,
      dealer_hand: ["10H", "9D"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    balance_before = Accounts.get_user!(scope.user.id).balance

    view |> element("#rebet-button") |> render_click()

    game_after = Games.get_active_blackjack_game(scope)
    assert Enum.map(game_after.hands, & &1["bet"]) == [25, 50]
    assert Accounts.get_user!(scope.user.id).balance == balance_before - 75
  end

  test "a round left mid dealer_turn (e.g. the LiveView process restarted before pacing finished) resumes on mount instead of freezing",
       %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_starting_chips(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 25})

    # rig a round stuck exactly where the self-scheduled `:dealer_step`
    # message would have been lost - the hole card is already revealed
    # (dealer_turn) and the dealer still needs to hit (16 < 17), but no
    # process is left holding the timer that would normally draw it
    game
    |> Games.BlackjackGame.changeset(%{
      status: "dealer_turn",
      shoe: ["5S"],
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 25,
          "cards" => ["4H", "8D"],
          "status" => "standing",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: nil,
      dealer_hand: ["6H", "JD"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    Enum.reduce_while(1..200, nil, fn _, _ ->
      if has_element?(view, "#rebet-button") do
        {:halt, nil}
      else
        Process.sleep(5)
        {:cont, nil}
      end
    end)

    game_after = Games.get_active_blackjack_game(scope)
    assert game_after.status == "round_over"
    assert game_after.dealer_hand == ["6H", "JD", "5S"]
  end

  test "standing on the first of two hands announces only the second hand's total, not both up front",
       %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_starting_chips(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 25, 1 => 25})

    # rig two still-untouched hands, as if freshly dealt - box 0 is active,
    # box 1 hasn't come up yet and should stay silent until it does
    game
    |> Games.BlackjackGame.changeset(%{
      status: "player_turn",
      shoe: [],
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 25,
          "cards" => ["9H", "8D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        },
        %{
          "id" => 1,
          "box" => 1,
          "bet" => 25,
          "cards" => ["7H", "6D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: 0,
      dealer_hand: ["10H", "7D"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    view |> element("#stand-button-0") |> render_click()

    assert_push_event(view, "play_sounds", %{sounds: ["player-stand", "thirteen"]})
  end

  test "a dealer natural blackjack settling a two-box round announces it once, not once per hand",
       %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_starting_chips(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 25, 1 => 25})

    # rig a round already sitting in dealer_turn with the dealer's two cards
    # already a natural blackjack (so the paced dealer_step below settles it
    # immediately, with no card left to draw) and two ordinary standing
    # hands that will both simply lose to it
    game
    |> Games.BlackjackGame.changeset(%{
      status: "dealer_turn",
      shoe: [],
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 25,
          "cards" => ["9H", "9D"],
          "status" => "standing",
          "outcome" => nil,
          "payout" => nil
        },
        %{
          "id" => 1,
          "box" => 1,
          "bet" => 25,
          "cards" => ["10H", "9S"],
          "status" => "standing",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: nil,
      dealer_hand: ["AS", "KD"]
    })
    |> HighSociety.Repo.update!()

    # mounting resumes the paced dealer_step this round was left mid-way
    # through (see the earlier dealer_turn-resume fix), which settles it
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    Enum.reduce_while(1..200, nil, fn _, _ ->
      if has_element?(view, "#rebet-button") do
        {:halt, nil}
      else
        Process.sleep(5)
        {:cont, nil}
      end
    end)

    assert Games.get_active_blackjack_game(scope).status == "round_over"
    assert_push_event(view, "play_sounds", %{sounds: ["dealer-blackjack"]})
  end
end
