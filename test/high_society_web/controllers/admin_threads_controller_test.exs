defmodule HighSocietyWeb.AdminThreadsControllerTest do
  use HighSocietyWeb.ConnCase, async: false

  alias HighSociety.Social

  setup :register_and_log_in_user

  setup do
    previous = Application.get_env(:high_society, :admin_emails, [])
    on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
    :ok
  end

  describe "connect/2" do
    test "redirects a guest to the log-in page" do
      conn = Phoenix.ConnTest.build_conn()
      conn = get(conn, ~p"/admin/threads/connect")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "forbids a non-admin", %{conn: conn} do
      Application.put_env(:high_society, :admin_emails, [])
      conn = get(conn, ~p"/admin/threads/connect")
      assert conn.status == 403
    end

    test "redirects an admin to Threads' consent screen", %{conn: conn, user: admin} do
      Application.put_env(:high_society, :admin_emails, [admin.email])
      conn = get(conn, ~p"/admin/threads/connect")

      assert redirected_to(conn, 302) =~ "https://threads.net/oauth/authorize?"
    end
  end

  describe "callback/2" do
    test "forbids a non-admin", %{conn: conn} do
      Application.put_env(:high_society, :admin_emails, [])
      conn = get(conn, ~p"/admin/threads/callback", %{"code" => "a-code"})
      assert conn.status == 403
    end

    test "on success, stores the connection and redirects to the review queue", %{
      conn: conn,
      user: admin
    } do
      Application.put_env(:high_society, :admin_emails, [admin.email])

      Req.Test.stub(HighSociety.Social.ThreadsClient, fn conn ->
        case conn.request_path do
          "/oauth/access_token" ->
            Req.Test.json(conn, %{"access_token" => "short-lived", "user_id" => 777})

          "/access_token" ->
            Req.Test.json(conn, %{"access_token" => "long-lived", "expires_in" => 5_184_000})

          "/v1.0/777" ->
            Req.Test.json(conn, %{"username" => "High_Societycc"})
        end
      end)

      conn = get(conn, ~p"/admin/threads/callback", %{"code" => "a-code"})

      assert redirected_to(conn) == ~p"/admin/social-posts"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Threads connected"

      connection = Social.current_threads_connection()
      assert connection.threads_user_id == "777"
      assert connection.access_token == "long-lived"
      assert connection.username == "High_Societycc"
    end

    test "on denial/error from Meta, redirects with a flash instead of crashing", %{
      conn: conn,
      user: admin
    } do
      Application.put_env(:high_society, :admin_emails, [admin.email])

      conn = get(conn, ~p"/admin/threads/callback", %{"error" => "access_denied"})

      assert redirected_to(conn) == ~p"/admin/social-posts"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cancelled or denied"
    end

    test "on a failed token exchange, redirects with an error flash", %{conn: conn, user: admin} do
      Application.put_env(:high_society, :admin_emails, [admin.email])

      Req.Test.stub(HighSociety.Social.ThreadsClient, fn conn ->
        Plug.Conn.send_resp(conn, 400, "")
      end)

      conn = get(conn, ~p"/admin/threads/callback", %{"code" => "a-code"})

      assert redirected_to(conn) == ~p"/admin/social-posts"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Couldn't connect Threads"
    end
  end
end
