defmodule HighSociety.Social.ThreadsClientTest do
  use ExUnit.Case, async: true

  alias HighSociety.Social.ThreadsClient

  describe "authorize_url/0" do
    test "points at threads.net with the app's client id and the fixed redirect URI" do
      url = ThreadsClient.authorize_url()

      assert url =~ "https://threads.net/oauth/authorize?"
      assert url =~ "client_id=test_threads_app_id"
      assert url =~ URI.encode_www_form("https://highsociety.cc/admin/threads/callback")
      assert url =~ "threads_basic"
      assert url =~ "threads_content_publish"
    end
  end

  describe "exchange_code/1" do
    test "returns the short-lived token and threads user id" do
      Req.Test.stub(ThreadsClient, fn conn ->
        assert conn.request_path == "/oauth/access_token"
        Req.Test.json(conn, %{"access_token" => "short-lived", "user_id" => 555})
      end)

      assert {:ok, %{access_token: "short-lived", threads_user_id: "555"}} =
               ThreadsClient.exchange_code("a-code")
    end

    test "returns an error tuple on a non-200 response" do
      Req.Test.stub(ThreadsClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "invalid_grant"}))
      end)

      assert {:error, {400, %{"error" => "invalid_grant"}}} =
               ThreadsClient.exchange_code("bad-code")
    end
  end

  describe "exchange_long_lived_token/1 and refresh_long_lived_token/1" do
    test "return the extended token and its lifetime" do
      Req.Test.stub(ThreadsClient, fn conn ->
        Req.Test.json(conn, %{"access_token" => "long-lived", "expires_in" => 5_184_000})
      end)

      assert {:ok, %{access_token: "long-lived", expires_in: 5_184_000}} =
               ThreadsClient.exchange_long_lived_token("short-lived")

      assert {:ok, %{access_token: "long-lived", expires_in: 5_184_000}} =
               ThreadsClient.refresh_long_lived_token("long-lived")
    end
  end

  describe "fetch_username/2" do
    test "returns the connected account's handle" do
      Req.Test.stub(ThreadsClient, fn conn ->
        assert conn.request_path == "/v1.0/555"
        Req.Test.json(conn, %{"username" => "High_Societycc"})
      end)

      assert {:ok, "High_Societycc"} = ThreadsClient.fetch_username("555", "a-token")
    end
  end

  describe "post_thread/3" do
    test "creates a container, then publishes it" do
      Req.Test.stub(ThreadsClient, fn conn ->
        cond do
          String.ends_with?(conn.request_path, "/threads") ->
            {:ok, body, _conn} = Plug.Conn.read_body(conn)
            assert body =~ "text=hello"
            Req.Test.json(conn, %{"id" => "container-1"})

          String.ends_with?(conn.request_path, "/threads_publish") ->
            Req.Test.json(conn, %{"id" => "published-1"})
        end
      end)

      assert {:ok, "published-1"} = ThreadsClient.post_thread("555", "a-token", "hello")
    end

    test "stops and returns an error if creating the container fails" do
      Req.Test.stub(ThreadsClient, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      assert {:error, {500, ""}} = ThreadsClient.post_thread("555", "a-token", "hello")
    end
  end
end
