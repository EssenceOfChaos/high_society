defmodule HighSocietyWeb.BadgesLiveTest do
  use HighSocietyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HighSociety.Repo

  setup :register_and_log_in_user

  test "redirects a guest to the log-in page" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/badges")
  end

  test "lists every badge with its tagline", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/badges")

    assert html =~ "Your Status"
    assert html =~ "Novice"
    assert html =~ "Just getting started."
    assert html =~ "High Society"
    assert html =~ "Among the elite."
  end

  test "explains that playing more raises status, without revealing the formula", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/badges")

    assert html =~ "The more you play, the more your status rises"
    refute html =~ "active_days_count"
    refute html =~ "day"
  end

  test "marks a brand new player's current badge as Novice", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/badges")

    assert html =~ ~s(id="badge-novice")
    assert html =~ "Current"
  end

  test "marks badges beyond the player's current status as locked", %{conn: conn, user: user} do
    user |> Ecto.Changeset.change(active_days_count: 5) |> Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/badges")

    assert has_element?(view, "#badge-skilled", "Current")
    refute has_element?(view, "#badge-novice", "Current")
    assert has_element?(view, "#badge-master .hero-lock-closed")
    refute has_element?(view, "#badge-skilled .hero-lock-closed")
  end
end
