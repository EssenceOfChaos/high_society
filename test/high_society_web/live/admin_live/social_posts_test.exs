defmodule HighSocietyWeb.AdminLive.SocialPostsTest do
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures

  alias HighSociety.Social
  alias HighSociety.Social.SocialPost

  setup :register_and_log_in_user

  setup do
    previous = Application.get_env(:high_society, :admin_emails, [])
    on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
    :ok
  end

  test "redirects a guest to the log-in page" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/social-posts")
  end

  test "redirects a non-admin user away with a flash", %{conn: conn} do
    Application.put_env(:high_society, :admin_emails, [])

    assert {:error, redirect} = live(conn, ~p"/admin/social-posts")
    assert {:redirect, %{to: "/", flash: flash}} = redirect
    assert flash["error"] =~ "don't have access"
  end

  test "shows Threads as not connected with a link to connect it", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])

    {:ok, _view, html} = live(conn, ~p"/admin/social-posts")

    assert html =~ "connect @High_Societycc"
    assert html =~ "/admin/threads/connect"
  end

  test "an admin can edit, then approve and post a pending X draft", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])
    social_post = pending_post_fixture("x")

    Req.Test.stub(HighSociety.Social.XClient, fn conn ->
      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"data" => %{"id" => "42"}})
    end)

    {:ok, view, html} = live(conn, ~p"/admin/social-posts")
    assert html =~ social_post.body

    view
    |> form("#social-post-#{social_post.id} form", %{"body" => "Edited congratulations!"})
    |> render_change()

    html =
      view
      |> element("#approve-social-post-#{social_post.id}")
      |> render_click()

    assert html =~ "Posted."
    assert html =~ "posted"

    updated = HighSociety.Repo.get!(SocialPost, social_post.id)
    assert updated.status == "posted"
    assert updated.platform_post_id == "42"
    assert updated.body == "Edited congratulations!"
    assert updated.reviewed_by_user_id == admin.id
  end

  test "an admin can reject a pending draft", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])
    social_post = pending_post_fixture("x")

    {:ok, view, _html} = live(conn, ~p"/admin/social-posts")

    html =
      view
      |> element("#reject-social-post-#{social_post.id}")
      |> render_click()

    assert html =~ "rejected"
    refute has_element?(view, "#approve-social-post-#{social_post.id}")

    updated = HighSociety.Repo.get!(SocialPost, social_post.id)
    assert updated.status == "rejected"
    assert updated.reviewed_by_user_id == admin.id
  end

  test "live-updates when a draft is created elsewhere", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])
    {:ok, view, html} = live(conn, ~p"/admin/social-posts")
    refute html =~ "poker_tournament_win"

    tournament = tournament_fixture(%{name: "Live Broadcast Open"})
    winner = user_fixture()
    Social.draft_tournament_win_post!(tournament, winner)

    assert render(view) =~ "Live Broadcast Open"
  end

  defp pending_post_fixture(platform) do
    tournament = tournament_fixture()

    %SocialPost{}
    |> SocialPost.create_changeset(%{
      platform: platform,
      source: "poker_tournament_win",
      body: "Congratulations to Ada for winning #{tournament.name}!",
      tournament_id: tournament.id
    })
    |> HighSociety.Repo.insert!()
  end
end
