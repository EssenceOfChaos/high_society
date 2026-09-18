defmodule HighSocietyWeb.TournamentGeoCheckTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "blocks registration from a restricted country, redirecting to the rules page", %{
    conn: conn
  } do
    conn = Plug.Conn.put_req_header(conn, "cf-ipcountry", "CN")

    assert {:error, {:redirect, %{to: "/tournament/rules"}}} = live(conn, ~p"/tournament")
  end

  test "blocks registration from a restricted US state, redirecting to the rules page", %{
    conn: conn
  } do
    conn =
      conn
      |> Plug.Conn.put_req_header("cf-ipcountry", "US")
      |> Plug.Conn.put_req_header("cf-region-code", "US-WA")

    assert {:error, {:redirect, %{to: "/tournament/rules"}}} = live(conn, ~p"/tournament")
  end

  test "allows registration from an unrestricted location", %{conn: conn} do
    conn =
      conn
      |> Plug.Conn.put_req_header("cf-ipcountry", "US")
      |> Plug.Conn.put_req_header("cf-region-code", "US-CA")

    assert {:ok, _view, html} = live(conn, ~p"/tournament")
    assert html =~ "Poker Tournament"
  end

  test "allows registration when Cloudflare headers are absent entirely (fails open)", %{
    conn: conn
  } do
    assert {:ok, _view, html} = live(conn, ~p"/tournament")
    assert html =~ "Poker Tournament"
  end

  test "spectating/results pages are never geo-blocked", %{conn: conn} do
    tournament = HighSociety.TournamentsFixtures.tournament_fixture()
    conn = Plug.Conn.put_req_header(conn, "cf-ipcountry", "CN")

    assert {:ok, _view, _html} = live(conn, ~p"/tournament/#{tournament.id}/tables")
    assert {:ok, _view, _html} = live(conn, ~p"/tournament/#{tournament.id}/results")
  end
end
