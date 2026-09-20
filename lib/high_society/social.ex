defmodule HighSociety.Social do
  @moduledoc """
  Drafts and sends posts to connected platforms (X, and Threads once an
  admin has connected `@High_Societycc` - see `connect_threads!/3`) for
  in-app events (so far just a tournament finishing). Every draft is
  created as `"pending"` and held for an admin to approve/edit/reject at
  `/admin/social-posts`, unless `:social_auto_post?` is enabled (a config
  flip, not a code change - see `config/runtime.exs` and `SOCIAL_AUTO_POST`),
  in which case it's posted immediately instead.
  """

  import Ecto.Query

  alias HighSociety.Accounts
  alias HighSociety.Repo
  alias HighSociety.Social.{SocialPost, ThreadsClient, ThreadsConnection, XClient}

  @topic "social_posts"

  @doc "The PubSub topic new drafts, status changes, and connection changes are broadcast on."
  def topic, do: @topic

  @doc """
  Drafts (or, with auto-post enabled, immediately sends) a tournament-win
  announcement for `winner` (the `User` who took first place in
  `tournament`) on every connected platform.
  """
  def draft_tournament_win_post!(tournament, winner) do
    body =
      "Congratulations to #{Accounts.display_name(winner)} for winning #{tournament.name}! \u{1F3C6}"

    for platform <- connected_platforms() do
      {:ok, social_post} =
        %SocialPost{}
        |> SocialPost.create_changeset(%{
          platform: platform,
          source: "poker_tournament_win",
          body: body,
          tournament_id: tournament.id
        })
        |> Repo.insert()

      social_post = if auto_post?(), do: post!(social_post, nil), else: social_post

      broadcast({:social_post_created, social_post})
      social_post
    end
  end

  @doc "Lists posts, most recently created first."
  def list_posts(limit \\ 100) do
    SocialPost
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Edits a still-pending draft's body before it's approved."
  def update_body(%SocialPost{status: "pending"} = social_post, body) do
    social_post
    |> SocialPost.body_changeset(%{body: body})
    |> Repo.update()
  end

  @doc "Approves a pending draft and posts it immediately."
  def approve_and_post!(%SocialPost{status: "pending"} = social_post, reviewer) do
    social_post =
      social_post
      |> SocialPost.reviewed_changeset(%{status: "approved", reviewed_by_user_id: reviewer.id})
      |> Repo.update!()
      |> post!(reviewer)

    broadcast({:social_post_updated, social_post})
    social_post
  end

  @doc "Rejects a pending draft - it's never sent."
  def reject!(%SocialPost{status: "pending"} = social_post, reviewer) do
    social_post =
      social_post
      |> SocialPost.reviewed_changeset(%{status: "rejected", reviewed_by_user_id: reviewer.id})
      |> Repo.update!()

    broadcast({:social_post_updated, social_post})
    social_post
  end

  @doc "The currently connected Threads account, if any."
  def current_threads_connection, do: Repo.one(ThreadsConnection)

  @doc """
  Stores (replacing any previous connection - only one Threads account is
  ever meaningful here) the result of the admin OAuth handshake, looking up
  the account's `@handle` for display.
  """
  def connect_threads!(threads_user_id, access_token, expires_at) do
    username =
      case ThreadsClient.fetch_username(threads_user_id, access_token) do
        {:ok, username} -> username
        {:error, _reason} -> nil
      end

    Repo.delete_all(ThreadsConnection)

    {:ok, connection} =
      %ThreadsConnection{}
      |> ThreadsConnection.changeset(%{
        threads_user_id: threads_user_id,
        username: username,
        access_token: access_token,
        expires_at: expires_at
      })
      |> Repo.insert()

    broadcast({:threads_connection_changed, connection})
    connection
  end

  @doc "Refreshes `connection`'s long-lived token in place. See `HighSociety.Social.ThreadsTokenRefresher`."
  def refresh_threads_connection!(%ThreadsConnection{} = connection) do
    case ThreadsClient.refresh_long_lived_token(connection.access_token) do
      {:ok, %{access_token: access_token, expires_in: expires_in}} ->
        connection
        |> ThreadsConnection.changeset(%{
          access_token: access_token,
          expires_at: DateTime.add(DateTime.utc_now(:second), expires_in, :second)
        })
        |> Repo.update!()

      {:error, _reason} = error ->
        error
    end
  end

  defp post!(social_post, reviewer) do
    social_post =
      case reviewer do
        nil ->
          social_post

        reviewer ->
          social_post |> Ecto.Changeset.change(reviewed_by_user_id: reviewer.id) |> Repo.update!()
      end

    case send_post(social_post) do
      {:ok, platform_post_id} ->
        social_post
        |> SocialPost.posted_changeset(%{
          status: "posted",
          platform_post_id: platform_post_id,
          posted_at: DateTime.utc_now(:second)
        })
        |> Repo.update!()

      {:error, reason} ->
        social_post
        |> SocialPost.posted_changeset(%{status: "failed", error: inspect(reason)})
        |> Repo.update!()
    end
  end

  defp send_post(%SocialPost{platform: "x", body: body}), do: XClient.post_tweet(body)

  defp send_post(%SocialPost{platform: "threads", body: body}) do
    case current_threads_connection() do
      nil ->
        {:error, :threads_not_connected}

      connection ->
        ThreadsClient.post_thread(connection.threads_user_id, connection.access_token, body)
    end
  end

  defp connected_platforms do
    if current_threads_connection(), do: ["x", "threads"], else: ["x"]
  end

  defp auto_post?, do: Application.get_env(:high_society, :social_auto_post?, false)

  defp broadcast(message), do: Phoenix.PubSub.broadcast(HighSociety.PubSub, @topic, message)
end
