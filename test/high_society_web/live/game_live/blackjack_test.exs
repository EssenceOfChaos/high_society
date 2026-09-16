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

    assert render(element(view, "#tokens-balance")) =~ "0 Tokens"
    assert has_element?(view, "#claim-blackjack-tokens-button")

    view |> element("#claim-blackjack-tokens-button") |> render_click()

    refute has_element?(view, "#claim-blackjack-tokens-button")
    assert render(element(view, "#tokens-balance")) =~ "500,000 Tokens"
  end

  test "chip buttons build up a pending bet, clamped at the 50,000 Tokens max", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    view |> element("#chip-0-10000") |> render_click()
    assert render(element(view, "#bet-amount-0")) =~ "10,000 Tokens"

    for _ <- 1..5, do: view |> element("#chip-0-10000") |> render_click()

    # 6 clicks of 10,000 would be 60,000, clamped down to the 50,000 Tokens max
    assert render(element(view, "#bet-amount-0")) =~ "50,000 Tokens"

    view |> element("#clear-bet-0") |> render_click()
    assert render(element(view, "#bet-amount-0")) =~ "0 Tokens"
    refute has_element?(view, "#clear-bet-0")
  end

  test "second hand starts hidden, can be added, and closing it clears its bet", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    refute has_element?(view, "#betting-box-1")
    assert has_element?(view, "#add-second-hand-button")

    view |> element("#add-second-hand-button") |> render_click()

    assert has_element?(view, "#betting-box-1")
    refute has_element?(view, "#add-second-hand-button")

    view |> element("#chip-1-10000") |> render_click()
    assert render(element(view, "#bet-amount-1")) =~ "10,000 Tokens"

    view |> element("#remove-second-hand-button") |> render_click()

    refute has_element?(view, "#betting-box-1")
    assert has_element?(view, "#add-second-hand-button")

    view |> element("#add-second-hand-button") |> render_click()
    assert render(element(view, "#bet-amount-1")) =~ "0 Tokens"
  end

  test "dealing with no claimed balance shows an inline error and creates no round", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    view |> element("#chip-0-2500") |> render_click()
    html = view |> element("#deal-button") |> render_click()

    assert html =~ "don&#39;t have enough Tokens"
    assert Games.get_active_blackjack_game(scope) == nil
  end

  test "a bet over the 50,000 Tokens max is rejected server-side even bypassing the UI clamp", %{
    scope: scope
  } do
    {:ok, _user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: Accounts.get_user!(scope.user.id)}

    assert {:error, :bet_too_large} =
             Games.start_blackjack_round(scope, %{0 => Blackjack.max_bet() + 1})

    assert Games.get_active_blackjack_game(scope) == nil
  end

  test "a full round: place a bet, deal, hit/stand to conclusion, and balance updates", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    view |> element("#claim-blackjack-tokens-button") |> render_click()

    view |> element("#chip-0-2500") |> render_click()
    html = view |> element("#deal-button") |> render_click()

    assert html =~ "Dealer"
    assert has_element?(view, "#hand-box-0")
    refute has_element?(view, "#betting-area")

    html =
      Enum.reduce_while(1..200, html, fn _, _ ->
        cond do
          has_element?(view, "#rebet-button") ->
            {:halt, render(view)}

          has_element?(view, "#insurance-no-button") ->
            # the dealer happened to show an Ace - decline so the round
            # plays out the same as any other deal
            {:cont, view |> element("#insurance-no-button") |> render_click()}

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

    assert updated_user.tokens_balance ==
             Accounts.blackjack_starting_token_amount() - 2_500 + total_payout
  end

  test "a dealer natural blackjack ends the round immediately, before any player action", %{
    conn: conn,
    scope: scope
  } do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}

    # keep dealing real (randomly shuffled) rounds until the dealer itself
    # is dealt a natural without showing an Ace - exercises the actual
    # `Blackjack.new/1` peek logic rather than rigging a persisted round to
    # fake the outcome. An Ace up-card is excluded since that instead pauses
    # on `:insurance_offered` - see the insurance tests further below.
    game =
      Stream.repeatedly(fn ->
        {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})
        game
      end)
      |> Enum.find(
        &(Blackjack.blackjack?(&1.dealer_hand) and
            not String.starts_with?(hd(&1.dealer_hand), "A"))
      )

    assert game.status == "round_over"

    {:ok, view, html} = live(conn, ~p"/games/blackjack")

    assert html =~ "Rebet"
    assert html =~ "Change bet"
    refute has_element?(view, "#betting-area")
    refute has_element?(view, "#hit-button-0")
    refute has_element?(view, "#double-button-0")
    refute has_element?(view, "#split-button-0")
  end

  test "the dealer's hole card is never sent to the client during the player's turn", %{
    conn: conn,
    scope: scope
  } do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

    # rig a deterministic dealer hand - the up card ("10H") should be
    # visible, the hole card ("7D") must not appear anywhere in the
    # rendered HTML (and therefore not in the LiveView diff sent over the
    # socket) while it's still face-down.
    game
    |> Games.BlackjackGame.changeset(%{
      status: "player_turn",
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 2_500,
          "cards" => ["6H", "5D"],
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

    html = render(view)
    assert html =~ ~s(alt="10H")
    refute html =~ ~s(alt="7D")
  end

  test "double down doubles the bet, draws exactly one card, and ends the hand's turn", %{
    conn: conn,
    scope: scope
  } do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

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
          "bet" => 2_500,
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
    assert hand["bet"] == 5_000
    assert hand["doubled"] == true

    assert Accounts.get_user!(user.id).tokens_balance ==
             Accounts.blackjack_starting_token_amount() - 2_500 - 2_500
  end

  test "splitting a pair plays out as two independent hands", %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

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
          "bet" => 2_500,
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

    assert Accounts.get_user!(user.id).tokens_balance ==
             Accounts.blackjack_starting_token_amount() - 2_500 - 2_500

    updated_game = Games.get_active_blackjack_game(scope)
    assert length(updated_game.hands) == 2
    assert Enum.map(updated_game.hands, & &1["bet"]) == [2_500, 2_500]

    # play the first split hand out, then the second becomes active
    view |> element("#stand-button-0") |> render_click()
    assert has_element?(view, "#stand-button-1")
  end

  test "Change bet returns to the betting UI without touching the persisted round", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    view |> element("#claim-blackjack-tokens-button") |> render_click()
    view |> element("#chip-0-2500") |> render_click()
    view |> element("#deal-button") |> render_click()

    Enum.reduce_while(1..200, nil, fn _, _ ->
      cond do
        has_element?(view, "#change-bet-button") ->
          {:halt, nil}

        has_element?(view, "#insurance-no-button") ->
          view |> element("#insurance-no-button") |> render_click()
          {:cont, nil}

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
    view |> element("#claim-blackjack-tokens-button") |> render_click()
    view |> element("#chip-0-2500") |> render_click()
    view |> element("#deal-button") |> render_click()

    Enum.reduce_while(1..200, nil, fn _, _ ->
      cond do
        has_element?(view, "#rebet-button") ->
          {:halt, nil}

        has_element?(view, "#insurance-no-button") ->
          view |> element("#insurance-no-button") |> render_click()
          {:cont, nil}

        has_element?(view, "#stand-button-0") ->
          view |> element("#stand-button-0") |> render_click()
          {:cont, nil}

        true ->
          Process.sleep(5)
          {:cont, nil}
      end
    end)

    game_before = Games.get_active_blackjack_game(scope)
    balance_before = Accounts.get_user!(scope.user.id).tokens_balance

    html = view |> element("#rebet-button") |> render_click()

    assert html =~ "Dealer"
    refute has_element?(view, "#betting-area")

    game_after = Games.get_active_blackjack_game(scope)
    assert game_after.id != game_before.id

    assert game_after.status in ["insurance_offered", "player_turn", "dealer_turn", "round_over"]

    assert Enum.map(game_after.hands, & &1["bet"]) == [2_500]
    assert Accounts.get_user!(scope.user.id).tokens_balance == balance_before - 2_500
  end

  test "Rebet on a two-box round re-deals both boxes at their original (pre-double) stakes", %{
    conn: conn,
    scope: scope
  } do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500, 1 => 5_000})

    # rig a settled two-box round with box 0 doubled, so the recovered
    # rebet stake for box 0 must be halved back to its original 25
    game
    |> Games.BlackjackGame.changeset(%{
      status: "round_over",
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 5_000,
          "cards" => ["6H", "5D", "2S"],
          "status" => "standing",
          "outcome" => "loss",
          "payout" => 0,
          "doubled" => true
        },
        %{
          "id" => 1,
          "box" => 1,
          "bet" => 5_000,
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
    balance_before = Accounts.get_user!(scope.user.id).tokens_balance

    view |> element("#rebet-button") |> render_click()

    game_after = Games.get_active_blackjack_game(scope)
    assert Enum.map(game_after.hands, & &1["bet"]) == [2_500, 5_000]
    assert Accounts.get_user!(scope.user.id).tokens_balance == balance_before - 7_500
  end

  test "a round left mid dealer_turn (e.g. the LiveView process restarted before pacing finished) resumes on mount instead of freezing",
       %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

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
          "bet" => 2_500,
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
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500, 1 => 2_500})

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
          "bet" => 2_500,
          "cards" => ["9H", "8D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        },
        %{
          "id" => 1,
          "box" => 1,
          "bet" => 2_500,
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
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500, 1 => 2_500})

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
          "bet" => 2_500,
          "cards" => ["9H", "9D"],
          "status" => "standing",
          "outcome" => nil,
          "payout" => nil
        },
        %{
          "id" => 1,
          "box" => 1,
          "bet" => 2_500,
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

  test "insurance is offered when the dealer shows an Ace, hiding the hole card and the usual actions",
       %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

    game
    |> Games.BlackjackGame.changeset(%{
      status: "insurance_offered",
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 2_500,
          "cards" => ["9H", "8D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: nil,
      dealer_hand: ["AS", "KD"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, html} = live(conn, ~p"/games/blackjack")

    assert html =~ "buy insurance"
    assert html =~ "2,500 Tokens"
    assert has_element?(view, "#insurance-yes-button")
    assert has_element?(view, "#insurance-no-button")
    refute has_element?(view, "#hit-button-0")
    refute has_element?(view, "#stand-button-0")

    html = render(view)
    assert html =~ ~s(alt="AS")
    refute html =~ ~s(alt="KD")
  end

  test "taking insurance against a dealer blackjack settles the round and pays 2 to 1", %{
    conn: conn,
    scope: scope
  } do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

    game
    |> Games.BlackjackGame.changeset(%{
      status: "insurance_offered",
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 2_500,
          "cards" => ["9H", "8D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: nil,
      dealer_hand: ["AS", "KD"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    balance_before = Accounts.get_user!(scope.user.id).tokens_balance

    html = view |> element("#insurance-yes-button") |> render_click()

    assert html =~ "Rebet"
    game_after = Games.get_active_blackjack_game(scope)
    assert game_after.status == "round_over"
    assert game_after.insurance_bet == 1_250
    assert game_after.insurance_outcome == "win"

    # -1,250 for insurance, +3,750 insurance payout, +0 on the lost main bet
    assert Accounts.get_user!(scope.user.id).tokens_balance == balance_before - 1_250 + 3_750
    assert_push_event(view, "play_sounds", %{sounds: ["dealer-blackjack"]})
  end

  test "taking insurance against a dealer without blackjack loses the side bet, plays the sound, and carries on",
       %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

    game
    |> Games.BlackjackGame.changeset(%{
      status: "insurance_offered",
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 2_500,
          "cards" => ["9H", "8D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: nil,
      dealer_hand: ["AS", "5D"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    balance_before = Accounts.get_user!(scope.user.id).tokens_balance

    view |> element("#insurance-yes-button") |> render_click()

    game_after = Games.get_active_blackjack_game(scope)
    assert game_after.status == "player_turn"
    assert game_after.insurance_bet == 1_250
    assert game_after.insurance_outcome == "loss"
    assert has_element?(view, "#hit-button-0")

    assert Accounts.get_user!(scope.user.id).tokens_balance == balance_before - 1_250
    assert_push_event(view, "play_sounds", %{sounds: ["dealer-no-blackjack"]})
  end

  test "declining insurance costs nothing and carries on as usual", %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

    game
    |> Games.BlackjackGame.changeset(%{
      status: "insurance_offered",
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 2_500,
          "cards" => ["9H", "8D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: nil,
      dealer_hand: ["AS", "5D"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")
    balance_before = Accounts.get_user!(scope.user.id).tokens_balance

    view |> element("#insurance-no-button") |> render_click()

    game_after = Games.get_active_blackjack_game(scope)
    assert game_after.status == "player_turn"
    assert game_after.insurance_bet == nil
    assert game_after.insurance_outcome == nil
    assert has_element?(view, "#hit-button-0")
    assert Accounts.get_user!(scope.user.id).tokens_balance == balance_before
    assert_push_event(view, "play_sounds", %{sounds: ["dealer-no-blackjack"]})
  end

  test "declining insurance still settles immediately, with the dealer-blackjack sound, if the dealer has blackjack",
       %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

    game
    |> Games.BlackjackGame.changeset(%{
      status: "insurance_offered",
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 2_500,
          "cards" => ["9H", "8D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: nil,
      dealer_hand: ["AS", "KD"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    view |> element("#insurance-no-button") |> render_click()

    assert Games.get_active_blackjack_game(scope).status == "round_over"
    assert_push_event(view, "play_sounds", %{sounds: ["dealer-blackjack"]})
  end

  test "taking insurance without enough balance to cover it shows an error and changes nothing",
       %{conn: conn, scope: scope} do
    {:ok, user} = Accounts.claim_blackjack_tokens(scope.user)
    scope = %{scope | user: user}
    {:ok, game} = Games.start_blackjack_round(scope, %{0 => 2_500})

    game
    |> Games.BlackjackGame.changeset(%{
      status: "insurance_offered",
      hands: [
        %{
          "id" => 0,
          "box" => 0,
          "bet" => 2_500,
          "cards" => ["9H", "8D"],
          "status" => "active",
          "outcome" => nil,
          "payout" => nil
        }
      ],
      active_hand: nil,
      dealer_hand: ["AS", "5D"]
    })
    |> HighSociety.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/games/blackjack")

    poor_user = Accounts.get_user!(scope.user.id)

    {:ok, poor_user} =
      Accounts.adjust_tokens_balance(poor_user, -(poor_user.tokens_balance - 10), "test_funding")

    html = view |> element("#insurance-yes-button") |> render_click()

    assert html =~ "don&#39;t have enough Tokens"
    assert has_element?(view, "#insurance-yes-button")
    assert Games.get_active_blackjack_game(scope).status == "insurance_offered"
    assert Accounts.get_user!(scope.user.id).tokens_balance == poor_user.tokens_balance
  end
end
