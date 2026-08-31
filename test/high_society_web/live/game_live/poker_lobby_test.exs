defmodule HighSocietyWeb.GameLive.PokerLobbyTest do
  # These read the same long-lived table processes the GenServer/LiveView
  # table tests reset between runs - see `HighSociety.PokerFixtures`.
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HighSociety.Games.PokerTables
  alias HighSociety.PokerFixtures

  setup :register_and_log_in_user

  setup do
    Enum.each(PokerTables.all(), &PokerFixtures.reset_table_around_test!(&1.slug))
    :ok
  end

  test "lists all three tables with their blinds and an empty seat count", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games/poker")

    assert has_element?(view, "#poker-table-new-york", "New York")
    assert has_element?(view, "#poker-table-new-york", "Blinds $1 / $2")
    assert has_element?(view, "#poker-table-new-york", "0 / 8 seated")
    assert has_element?(view, "#poker-table-paris", "Paris")
    assert has_element?(view, "#poker-table-london", "London")
  end
end
