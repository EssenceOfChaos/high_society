defmodule HighSocietyWeb.AdminLive.SocialPosts do
  @moduledoc """
  Admin review queue for posts to connected platforms (X, and Threads once
  connected) drafted off in-app events (see
  `HighSociety.Social.draft_tournament_win_post!/2`). Pending drafts can be
  edited before being approved (which posts immediately) or rejected
  (which discards them). Gated by the `:require_admin` on_mount - see
  `HighSocietyWeb.UserAuth`.
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Social

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(HighSociety.PubSub, Social.topic())

    {:ok,
     socket
     |> assign(:page_title, "Social posts")
     |> assign(:posts, Social.list_posts())
     |> assign(:threads_connection, Social.current_threads_connection())}
  end

  @impl true
  def handle_event("update_body", %{"id" => id, "body" => body}, socket) do
    id |> String.to_integer() |> find_post(socket) |> Social.update_body(body)
    {:noreply, refresh(socket)}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    id
    |> String.to_integer()
    |> find_post(socket)
    |> Social.approve_and_post!(socket.assigns.current_scope.user)

    {:noreply, socket |> put_flash(:info, "Posted.") |> refresh()}
  end

  def handle_event("reject", %{"id" => id}, socket) do
    id
    |> String.to_integer()
    |> find_post(socket)
    |> Social.reject!(socket.assigns.current_scope.user)

    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:social_post_created, :social_post_updated, :threads_connection_changed] do
    {:noreply, refresh(socket)}
  end

  defp find_post(id, socket), do: Enum.find(socket.assigns.posts, &(&1.id == id))

  defp refresh(socket) do
    socket
    |> assign(:posts, Social.list_posts())
    |> assign(:threads_connection, Social.current_threads_connection())
  end

  defp status_badge_class("pending"), do: "badge-warning"
  defp status_badge_class("approved"), do: "badge-info"
  defp status_badge_class("posted"), do: "badge-success"
  defp status_badge_class("rejected"), do: "badge-neutral"
  defp status_badge_class("failed"), do: "badge-error"

  defp platform_label("x"), do: "X"
  defp platform_label("threads"), do: "Threads"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <.header>
          Social posts
          <:subtitle>
            Drafts created automatically from in-app events, held for approval before posting.
          </:subtitle>
        </.header>

        <div class="mt-4 rounded-box border border-base-300 bg-base-100 p-4 text-sm">
          <span :if={@threads_connection} class="text-success">
            Threads connected as @{@threads_connection.username || @threads_connection.threads_user_id}
          </span>
          <span :if={!@threads_connection}>
            Threads isn't connected yet -
            <.link navigate="/admin/threads/connect" class="link">connect @High_Societycc</.link>
          </span>
        </div>

        <p :if={@posts == []} class="mt-6 text-sm text-base-content/60">
          No posts yet.
        </p>

        <div
          :for={post <- @posts}
          id={"social-post-#{post.id}"}
          class="mt-4 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span class="badge badge-outline">{platform_label(post.platform)}</span>
              <span class={["badge", status_badge_class(post.status)]}>{post.status}</span>
            </div>
            <span class="text-xs text-base-content/60">{post.source}</span>
          </div>

          <form
            :if={post.status == "pending"}
            id={"social-post-form-#{post.id}"}
            phx-change="update_body"
            phx-value-id={post.id}
            class="mt-2"
          >
            <textarea
              name="body"
              rows="3"
              class="textarea textarea-bordered w-full"
              phx-debounce="500"
            >{post.body}</textarea>
          </form>

          <p :if={post.status != "pending"} class="mt-2 whitespace-pre-wrap text-sm">
            {post.body}
          </p>

          <p :if={post.status == "failed"} class="mt-2 text-sm text-error">
            {post.error}
          </p>

          <p :if={post.status == "posted"} class="mt-2 text-xs text-base-content/60">
            Posted {post.posted_at} - id {post.platform_post_id}
          </p>

          <div :if={post.status == "pending"} class="mt-3 flex gap-2">
            <button
              phx-click="approve"
              phx-value-id={post.id}
              id={"approve-social-post-#{post.id}"}
              class="btn btn-sm btn-primary"
              data-confirm={"Post this to #{platform_label(post.platform)} now? This can't be undone."}
            >
              Approve &amp; post
            </button>
            <button
              phx-click="reject"
              phx-value-id={post.id}
              id={"reject-social-post-#{post.id}"}
              class="btn btn-sm btn-ghost"
            >
              Reject
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
