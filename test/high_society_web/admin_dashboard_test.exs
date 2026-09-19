defmodule HighSocietyWeb.AdminDashboardTest do
  @moduledoc """
  Covers the auth gate on the prod-reachable `/admin/dashboard` LiveDashboard
  mount (see `HighSocietyWeb.Router`) - mirrors the same guest/non-admin/admin
  cases as `HighSocietyWeb.AdminLive.TokenTransactionsTest`, since this route
  uses the identical `:require_authenticated` + `:require_admin` on_mount
  chain rather than the dev-only, unauthenticated `/dev/dashboard` mount.
  """
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  setup do
    previous = Application.get_env(:high_society, :admin_emails, [])
    on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
    :ok
  end

  test "redirects a guest to the log-in page" do
    conn = Phoenix.ConnTest.build_conn()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/dashboard")
  end

  test "redirects a non-admin user away with a flash", %{conn: conn} do
    Application.put_env(:high_society, :admin_emails, [])

    assert {:error, redirect} = live(conn, ~p"/admin/dashboard")
    assert {:redirect, %{to: "/", flash: flash}} = redirect
    assert flash["error"] =~ "don't have access"
  end

  test "an admin can reach the dashboard, including the ecto_psql_extras-powered Ecto Stats page",
       %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    assert {:error, {:live_redirect, %{to: "/admin/dashboard/home"}}} =
             live(conn, ~p"/admin/dashboard")

    {:ok, _view, html} = live(conn, ~p"/admin/dashboard/home")
    assert html =~ "Phoenix LiveDashboard"

    {:ok, _view, html} = live(conn, ~p"/admin/dashboard/ecto_stats")
    assert html =~ "Ecto Stats"
  end
end
