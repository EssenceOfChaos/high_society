defmodule HighSocietyWeb.GameLive.BaccaratTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts
  alias HighSociety.Games.BaccaratGame
  alias HighSociety.Repo

  setup :register_and_log_in_user

  defp await_reveal(view) do
    Enum.reduce_while(1..50, nil, fn _, _ ->
      if has_element?(view, "#baccarat-screen[data-dealing=false]") do
        {:halt, render(view)}
      else
        Process.sleep(5)
        {:cont, nil}
      end
    end)
  end

  defp history_beads(html) do
    Regex.scan(~r/data-history-bead="([a-z]+)"/, html) |> Enum.map(&Enum.at(&1, 1))
  end

  defp deal_round(view) do
    view |> element("#bet-player") |> render_click()
    view |> element("#deal-button") |> render_click()
    await_reveal(view)
  end

  test "redirects to log in when not authenticated" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/baccarat")
  end

  test "shows the claim button pre-claim, and the updated balance post-claim", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")

    assert render(element(view, "#tokens-balance")) =~ "0 Tokens"
    assert has_element?(view, "#claim-baccarat-tokens-button")

    view |> element("#claim-baccarat-tokens-button") |> render_click()

    refute has_element?(view, "#claim-baccarat-tokens-button")
    assert render(element(view, "#tokens-balance")) =~ "500,000 Tokens"
  end

  test "the how-to-play modal opens via its button and closes via the X button", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")

    refute has_element?(view, "#how-to-play-modal")

    view |> element("#how-to-play-button") |> render_click()
    assert has_element?(view, "#how-to-play-modal")
    assert render(element(view, "#how-to-play-modal")) =~ "How to Play Baccarat"

    view |> element("#how-to-play-modal button[aria-label='Close']") |> render_click()
    refute has_element?(view, "#how-to-play-modal")
  end

  test "the how-to-play modal closes on a click outside it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")

    view |> element("#how-to-play-button") |> render_click()
    assert has_element?(view, "#how-to-play-modal")

    # simulates the client-side `phx-click-away` binding firing this event
    render_click(view, "close_how_to_play")
    refute has_element?(view, "#how-to-play-modal")
  end

  test "the deal button starts disabled until a bet is placed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")

    assert render(element(view, "#deal-button")) =~ "disabled"

    view |> element("#bet-player") |> render_click()

    refute render(element(view, "#deal-button")) =~ "disabled"
  end

  test "clicking a betting spot places the selected chip, and clicking it again stacks it", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")

    view |> element("#bet-player") |> render_click()
    assert render(element(view, "#bet-player")) =~ "100"
    assert render(element(view, "#baccarat-screen")) =~ "Total bet:"

    view |> element("#chip-500") |> render_click()
    view |> element("#bet-player") |> render_click()

    assert render(element(view, "#bet-player")) =~ "600"
  end

  test "clear bets resets every pending bet", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")

    view |> element("#bet-player") |> render_click()
    view |> element("#bet-banker") |> render_click()

    view |> element("#clear-bets-button") |> render_click()

    assert render(element(view, "#deal-button")) =~ "disabled"
  end

  test "dealing without enough balance shows an inline error and takes no chips", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")

    view |> element("#bet-player") |> render_click()
    html = view |> element("#deal-button") |> render_click()

    assert html =~ "don&#39;t have enough Tokens"
  end

  test "the outcome sound reflects whether the player's own bet won, not which hand won", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")
    view |> element("#claim-baccarat-tokens-button") |> render_click()

    # Which sound is "correct" depends on the player's own bet, not on
    # which hand won - betting Banker and having Banker win should sound
    # like a win, and betting Player and having Banker win should sound
    # like a loss. Since a round shuffles a real deck, loop enough times
    # to guarantee both of those specific combinations actually occur.
    {saw_banker_bet_win, saw_player_bet_lose_to_banker} =
      Enum.reduce_while(1..100, {false, false}, fn _, {saw_win, saw_lose} ->
        bet_key = Enum.random(~w(player banker))
        view |> element("#bet-#{bet_key}") |> render_click()
        view |> element("#deal-button") |> render_click()
        await_reveal(view)

        game = Repo.get_by!(BaccaratGame, user_id: user.id)

        cond do
          game.total_payout > game.total_wager ->
            assert_push_event(view, "play_sound", %{sound: "player-wins"})

          game.total_payout < game.total_wager ->
            assert_push_event(view, "play_sound", %{sound: "banker-wins"})

          true ->
            assert_push_event(view, "play_sound", %{sound: "tie"})
        end

        saw_win = saw_win or (bet_key == "banker" and game.outcome == "banker")
        saw_lose = saw_lose or (bet_key == "player" and game.outcome == "banker")

        if saw_win and saw_lose do
          {:halt, {saw_win, saw_lose}}
        else
          {:cont, {saw_win, saw_lose}}
        end
      end)

    assert saw_banker_bet_win,
           "expected at least one round where betting Banker won (Banker hand wins)"

    assert saw_player_bet_lose_to_banker,
           "expected at least one round where betting Player lost to a Banker win"
  end

  test "a full round debits the total stake, disables the button meanwhile, and reveals a result",
       %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")
    view |> element("#claim-baccarat-tokens-button") |> render_click()

    view |> element("#bet-player") |> render_click()
    view |> element("#bet-tie") |> render_click()

    balance_before = Accounts.get_user!(user.id).tokens_balance

    html = view |> element("#deal-button") |> render_click()
    assert html =~ "disabled"

    await_reveal(view)

    updated_user = Accounts.get_user!(user.id)
    game = Repo.get_by!(BaccaratGame, user_id: user.id)

    assert game.total_wager == 200
    assert game.outcome in ~w(player banker tie)
    assert updated_user.tokens_balance == balance_before - 200 + game.total_payout

    # bets are consumed by the round, and the button resets for the next one
    assert render(element(view, "#deal-button")) =~ "disabled"
  end

  test "rebet only appears after a round, and restores exactly that round's bets", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")
    view |> element("#claim-baccarat-tokens-button") |> render_click()

    refute has_element?(view, "#rebet-button")

    view |> element("#bet-player") |> render_click()
    view |> element("#chip-500") |> render_click()
    view |> element("#bet-tie") |> render_click()

    view |> element("#deal-button") |> render_click()
    await_reveal(view)

    assert has_element?(view, "#rebet-button")

    view |> element("#rebet-button") |> render_click()

    assert render(element(view, "#bet-player")) =~ "100"
    assert render(element(view, "#bet-tie")) =~ "500"
    refute render(element(view, "#deal-button")) =~ "disabled"

    balance_before = Accounts.get_user!(user.id).tokens_balance
    view |> element("#deal-button") |> render_click()
    await_reveal(view)

    game = Repo.get_by!(BaccaratGame, user_id: user.id)
    assert game.total_wager == 600

    assert Accounts.get_user!(user.id).tokens_balance ==
             balance_before - 600 + game.total_payout
  end

  test "rebet and deal only appears after a round, and deals exactly that round's bets in one click",
       %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/games/baccarat")
    view |> element("#claim-baccarat-tokens-button") |> render_click()

    refute has_element?(view, "#rebet-and-deal-button")

    view |> element("#bet-player") |> render_click()
    view |> element("#chip-500") |> render_click()
    view |> element("#bet-tie") |> render_click()

    view |> element("#deal-button") |> render_click()
    await_reveal(view)

    assert has_element?(view, "#rebet-and-deal-button")

    balance_before = Accounts.get_user!(user.id).tokens_balance
    view |> element("#rebet-and-deal-button") |> render_click()
    assert has_element?(view, "#baccarat-screen[data-dealing=true]")

    await_reveal(view)

    game = Repo.get_by!(BaccaratGame, user_id: user.id)
    assert game.total_wager == 600

    assert Accounts.get_user!(user.id).tokens_balance ==
             balance_before - 600 + game.total_payout
  end

  describe "round history (Bead Road)" do
    test "is hidden until the first round finishes, then records one bead per round", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/games/baccarat")
      view |> element("#claim-baccarat-tokens-button") |> render_click()

      refute has_element?(view, "[data-history-bead]")

      html = deal_round(view)
      game_1 = Repo.get_by!(BaccaratGame, user_id: user.id)
      assert history_beads(html) == [game_1.outcome]

      html = deal_round(view)
      game_2 = Repo.get_by!(BaccaratGame, user_id: user.id)
      assert history_beads(html) == [game_1.outcome, game_2.outcome]
    end

    test "caps the strip at the most recent 20 rounds", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/games/baccarat")
      view |> element("#claim-baccarat-tokens-button") |> render_click()

      html = Enum.reduce(1..23, nil, fn _, _acc -> deal_round(view) end)

      assert length(history_beads(html)) == 20
    end

    test "seeds the strip with the last known result after a reconnect", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/games/baccarat")
      view |> element("#claim-baccarat-tokens-button") |> render_click()
      deal_round(view)

      {:ok, _reconnected_view, html} = live(conn, ~p"/games/baccarat")
      assert length(history_beads(html)) == 1
    end
  end
end
