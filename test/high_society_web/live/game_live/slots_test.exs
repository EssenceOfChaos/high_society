defmodule HighSocietyWeb.GameLive.SlotsTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Accounts
  alias HighSociety.Games.Slots
  alias HighSociety.Games.SlotsGame
  alias HighSociety.Money
  alias HighSociety.Repo

  setup :register_and_log_in_user

  # Waits out a full spin cycle rather than just checking "not spinning" -
  # a free-spins round starts out not-spinning too (it only flips to
  # spinning once its own auto-advance timer fires), so checking for the
  # "false" state alone would return immediately, before the spin happens.
  defp await_reveal(view) do
    await_spinning(view, true)
    await_spinning(view, false)
    render(view)
  end

  defp await_spinning(view, spinning?) do
    Enum.reduce_while(1..50, nil, fn _, _ ->
      if has_element?(view, "#slots-screen[data-spinning=#{spinning?}]") do
        {:halt, :ok}
      else
        Process.sleep(5)
        {:cont, nil}
      end
    end)
  end

  test "redirects to log in when not authenticated" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/games/slots")
  end

  test "shows the claim button pre-claim, and the updated balance post-claim", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/slots")

    assert render(element(view, "#balance")) =~ "$0"
    assert has_element?(view, "#claim-chips-button")

    view |> element("#claim-chips-button") |> render_click()

    refute has_element?(view, "#claim-chips-button")
    assert render(element(view, "#balance")) =~ "$10,000"
  end

  test "shows all 12 wager options in the dropdown, cheapest selected by default", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/slots")

    for amount <- Slots.wager_options() do
      assert has_element?(view, "#wager-select option[value='#{amount}']")
    end

    assert has_element?(view, "#wager-select option[value='25'][selected]")
  end

  test "picking a different wager changes the selection and the spin button label", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/slots")

    view |> element("#wager-form") |> render_change(%{"amount" => "500"})

    assert has_element?(view, "#wager-select option[value='500'][selected]")
    refute has_element?(view, "#wager-select option[value='25'][selected]")
    assert render(element(view, "#spin-button")) =~ "$5.00"
  end

  test "spinning without enough balance shows an inline error and takes no chips", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/slots")

    html = view |> element("#spin-button") |> render_click()

    assert html =~ "don&#39;t have enough chips"
  end

  test "a full spin debits the wager, disables the button meanwhile, and reveals a result", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/games/slots")
    view |> element("#claim-chips-button") |> render_click()
    view |> element("#wager-form") |> render_change(%{"amount" => "100"})

    balance_before = Accounts.get_user!(user.id).balance

    html = view |> element("#spin-button") |> render_click()
    assert html =~ "disabled"

    await_reveal(view)

    updated_user = Accounts.get_user!(user.id)
    game = Repo.get_by!(SlotsGame, user_id: user.id)

    assert game.wager == 100
    assert updated_user.balance == balance_before - 100 + game.total_win
    assert has_element?(view, "#slots-grid")
  end

  test "an active free-spins round locks the wager selector and spins automatically", %{
    conn: conn,
    user: user
  } do
    {:ok, user} = Accounts.claim_slots_chips(user)

    %SlotsGame{}
    |> SlotsGame.changeset(%{
      user_id: user.id,
      grid: List.duplicate("cherries", 24),
      wager: 200,
      total_win: 0,
      free_spins_remaining: 3,
      free_spin_multiplier: Slots.free_spin_multiplier(),
      triggering_wager: 200,
      spins_taken: 1
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/games/slots")

    assert render(view) =~ "Free Spins remaining: 3"
    refute has_element?(view, "#wager-form")
    refute has_element?(view, "#spin-button")
    assert has_element?(view, "#auto-spin-indicator")

    balance_before = Accounts.get_user!(user.id).balance

    # No click needed - an active free-spins round advances on its own.
    # Under test the reveal/auto-advance delays are tiny, so by the time
    # this observes a completed cycle, more than one free spin may already
    # have fired in the background - assert the invariants that hold no
    # matter how many did (wager never changes, balance never drops, since
    # free spins don't debit).
    await_reveal(view)

    updated_user = Accounts.get_user!(user.id)
    game = Repo.get_by!(SlotsGame, user_id: user.id)

    assert game.wager == 200
    assert game.spins_taken > 1
    assert updated_user.balance >= balance_before
  end

  test "a free-spins round keeps spinning itself out until it's exhausted", %{
    conn: conn,
    user: user
  } do
    {:ok, user} = Accounts.claim_slots_chips(user)

    %SlotsGame{}
    |> SlotsGame.changeset(%{
      user_id: user.id,
      grid: List.duplicate("cherries", 24),
      wager: 200,
      total_win: 0,
      free_spins_remaining: 1,
      free_spin_multiplier: Slots.free_spin_multiplier(),
      triggering_wager: 200,
      spins_taken: 1
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/games/slots")

    await_reveal(view)

    game = Repo.get_by!(SlotsGame, user_id: user.id)

    # The one queued free spin always fires; on the rare draw where it also
    # relands a fresh bonus, the round keeps going instead of ending here.
    if game.free_spins_remaining == 0 do
      assert has_element?(view, "#spin-button")
      refute has_element?(view, "#auto-spin-indicator")
      refute render(view) =~ "Free Spins remaining"
    else
      assert has_element?(view, "#auto-spin-indicator")
    end
  end

  test "shows the bonus round's running total once it ends, alongside the per-spin result", %{
    conn: conn,
    user: user
  } do
    {:ok, user} = Accounts.claim_slots_chips(user)

    %SlotsGame{}
    |> SlotsGame.changeset(%{
      user_id: user.id,
      grid: List.duplicate("cherries", 24),
      wager: 200,
      total_win: 0,
      free_spins_remaining: 1,
      free_spin_multiplier: Slots.free_spin_multiplier(),
      triggering_wager: 200,
      spins_taken: 1
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/games/slots")

    refute render(view) =~ "Bonus round total"

    await_reveal(view)

    game = Repo.get_by!(SlotsGame, user_id: user.id)
    html = render(view)

    # The one queued free spin always fires; on the rare draw where it also
    # relands a fresh bonus, the round keeps going instead of ending here,
    # so there's no total to show yet - same caveat as the test above.
    if game.free_spins_remaining == 0 do
      assert html =~ "Bonus round total: $#{Money.format(game.total_win)}"
    else
      refute html =~ "Bonus round total"
    end
  end
end
