defmodule HighSociety.SocialTest do
  use HighSociety.DataCase, async: true

  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures

  alias HighSociety.Repo
  alias HighSociety.Social
  alias HighSociety.Social.{SocialPost, ThreadsConnection}

  setup do
    Phoenix.PubSub.subscribe(HighSociety.PubSub, Social.topic())
    :ok
  end

  describe "draft_tournament_win_post!/2" do
    test "drafts a pending X post when Threads isn't connected" do
      tournament = tournament_fixture(%{name: "Sunday Showdown"})
      winner = user_fixture()

      [social_post] = Social.draft_tournament_win_post!(tournament, winner)

      assert social_post.platform == "x"
      assert social_post.status == "pending"
      assert social_post.source == "poker_tournament_win"
      assert social_post.tournament_id == tournament.id
      assert social_post.body =~ HighSociety.Accounts.display_name(winner)
      assert social_post.body =~ "Sunday Showdown"
      assert_received {:social_post_created, ^social_post}
    end

    test "also drafts a Threads post once an account is connected" do
      threads_connection_fixture()
      tournament = tournament_fixture()
      winner = user_fixture()

      posts = Social.draft_tournament_win_post!(tournament, winner)

      assert Enum.map(posts, & &1.platform) |> Enum.sort() == ["threads", "x"]
      assert Enum.all?(posts, &(&1.status == "pending"))
    end

    test "posts immediately when social_auto_post? is enabled" do
      Application.put_env(:high_society, :social_auto_post?, true)
      on_exit(fn -> Application.put_env(:high_society, :social_auto_post?, false) end)

      Req.Test.stub(HighSociety.Social.XClient, fn conn ->
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"data" => %{"id" => "12345"}})
      end)

      tournament = tournament_fixture()
      winner = user_fixture()

      [social_post] = Social.draft_tournament_win_post!(tournament, winner)

      assert social_post.status == "posted"
      assert social_post.platform_post_id == "12345"
      assert social_post.posted_at != nil
    end
  end

  describe "approve_and_post!/2" do
    test "posts a pending X draft and marks it posted" do
      reviewer = user_fixture()
      social_post = pending_post_fixture("x")

      Req.Test.stub(HighSociety.Social.XClient, fn conn ->
        assert ["OAuth " <> _] = Plug.Conn.get_req_header(conn, "authorization")
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"data" => %{"id" => "999"}})
      end)

      updated = Social.approve_and_post!(social_post, reviewer)

      assert updated.status == "posted"
      assert updated.platform_post_id == "999"
      assert updated.reviewed_by_user_id == reviewer.id
      assert_received {:social_post_updated, ^updated}
    end

    test "posts a pending Threads draft via the container-then-publish flow" do
      connection = threads_connection_fixture()
      reviewer = user_fixture()
      social_post = pending_post_fixture("threads")

      Req.Test.stub(HighSociety.Social.ThreadsClient, fn conn ->
        case conn.request_path do
          "/v1.0/" <> _ = path ->
            cond do
              String.ends_with?(path, "/threads") ->
                Req.Test.json(conn, %{"id" => "container-1"})

              String.ends_with?(path, "/threads_publish") ->
                Req.Test.json(conn, %{"id" => "published-1"})
            end
        end
      end)

      updated = Social.approve_and_post!(social_post, reviewer)

      assert updated.status == "posted"
      assert updated.platform_post_id == "published-1"
      assert connection.threads_user_id
    end

    test "marks the draft failed when the platform rejects the post" do
      reviewer = user_fixture()
      social_post = pending_post_fixture("x")

      Req.Test.stub(HighSociety.Social.XClient, fn conn ->
        Plug.Conn.send_resp(conn, 403, Jason.encode!(%{"detail" => "Forbidden"}))
      end)

      updated = Social.approve_and_post!(social_post, reviewer)

      assert updated.status == "failed"
      assert updated.error =~ "403"
    end

    test "marks a Threads draft failed if the account was never connected" do
      reviewer = user_fixture()
      social_post = pending_post_fixture("threads")

      updated = Social.approve_and_post!(social_post, reviewer)

      assert updated.status == "failed"
      assert updated.error =~ "threads_not_connected"
    end
  end

  describe "reject!/2" do
    test "marks the draft rejected without posting" do
      reviewer = user_fixture()
      social_post = pending_post_fixture("x")

      updated = Social.reject!(social_post, reviewer)

      assert updated.status == "rejected"
      assert updated.reviewed_by_user_id == reviewer.id
      assert_received {:social_post_updated, ^updated}
    end
  end

  describe "update_body/2" do
    test "edits a pending draft's body" do
      social_post = pending_post_fixture("x")

      assert {:ok, updated} = Social.update_body(social_post, "Updated copy")
      assert updated.body == "Updated copy"
    end
  end

  describe "connect_threads!/3 and refresh_threads_connection!/1" do
    test "stores the connection, looking up the account's username" do
      Req.Test.stub(HighSociety.Social.ThreadsClient, fn conn ->
        Req.Test.json(conn, %{"username" => "High_Societycc"})
      end)

      expires_at = DateTime.add(DateTime.utc_now(:second), 60 * 24 * 60 * 60, :second)
      connection = Social.connect_threads!("123", "long-lived-token", expires_at)

      assert connection.threads_user_id == "123"
      assert connection.username == "High_Societycc"
      assert connection.access_token == "long-lived-token"
      assert_received {:threads_connection_changed, ^connection}
    end

    test "replaces any previous connection" do
      Req.Test.stub(HighSociety.Social.ThreadsClient, fn conn ->
        Req.Test.json(conn, %{"username" => "High_Societycc"})
      end)

      expires_at = DateTime.add(DateTime.utc_now(:second), 60 * 24 * 60 * 60, :second)
      Social.connect_threads!("111", "token-a", expires_at)
      Social.connect_threads!("222", "token-b", expires_at)

      assert Repo.aggregate(ThreadsConnection, :count) == 1
      assert Social.current_threads_connection().threads_user_id == "222"
    end

    test "refresh_threads_connection!/1 extends the stored token" do
      connection = threads_connection_fixture()

      Req.Test.stub(HighSociety.Social.ThreadsClient, fn conn ->
        Req.Test.json(conn, %{"access_token" => "refreshed-token", "expires_in" => 5_184_000})
      end)

      updated = Social.refresh_threads_connection!(connection)

      assert updated.access_token == "refreshed-token"
      assert DateTime.compare(updated.expires_at, connection.expires_at) == :gt
    end
  end

  defp threads_connection_fixture do
    %ThreadsConnection{}
    |> ThreadsConnection.changeset(%{
      threads_user_id: "42",
      username: "High_Societycc",
      access_token: "a-long-lived-token",
      expires_at: DateTime.add(DateTime.utc_now(:second), 30 * 24 * 60 * 60, :second)
    })
    |> Repo.insert!()
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
    |> Repo.insert!()
  end
end
