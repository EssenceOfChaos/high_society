defmodule HighSocietyWeb.AdminLive.InboundEmails do
  @moduledoc """
  Admin review queue for emails received at the `mail.highsociety.cc`
  inbound domain (see `HighSociety.Support.receive_inbound_email/1`), each
  held as a pending draft with an AI-suggested category/reply (see
  `HighSociety.Support.ClaudeClient`) until approved (which emails the
  reply to the original sender) or rejected. Gated by the `:require_admin`
  on_mount - see `HighSocietyWeb.UserAuth`.
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Support
  alias HighSociety.Support.Report

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(HighSociety.PubSub, Support.topic())

    {:ok,
     socket
     |> assign(:page_title, "Inbound emails")
     |> assign(:emails, Support.list_inbound_emails())}
  end

  @impl true
  def handle_event("update_draft_reply", %{"id" => id, "draft_reply" => draft_reply}, socket) do
    id |> String.to_integer() |> find_email(socket) |> Support.update_draft_reply(draft_reply)
    {:noreply, refresh(socket)}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    id
    |> String.to_integer()
    |> find_email(socket)
    |> Support.approve_and_send!(socket.assigns.current_scope.user)

    {:noreply, socket |> put_flash(:info, "Reply sent.") |> refresh()}
  end

  def handle_event("reject", %{"id" => id}, socket) do
    id
    |> String.to_integer()
    |> find_email(socket)
    |> Support.reject!(socket.assigns.current_scope.user)

    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:inbound_email_created, :inbound_email_updated] do
    {:noreply, refresh(socket)}
  end

  defp find_email(id, socket), do: Enum.find(socket.assigns.emails, &(&1.id == id))

  defp refresh(socket), do: assign(socket, :emails, Support.list_inbound_emails())

  defp status_badge_class("pending"), do: "badge-warning"
  defp status_badge_class("approved"), do: "badge-info"
  defp status_badge_class("sent"), do: "badge-success"
  defp status_badge_class("rejected"), do: "badge-neutral"
  defp status_badge_class("failed"), do: "badge-error"

  defp category_label(nil), do: nil
  defp category_label(category), do: Report.category_label(category)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <.header>
          Inbound emails
          <:subtitle>
            Emails received at the support inbound address, with an AI-drafted
            category and reply held for approval before anything is sent.
          </:subtitle>
        </.header>

        <p :if={@emails == []} class="mt-6 text-sm text-base-content/60">
          No inbound emails yet.
        </p>

        <div
          :for={email <- @emails}
          id={"inbound-email-#{email.id}"}
          class="mt-4 rounded-box border border-base-300 bg-base-100 p-4"
        >
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span
                :if={category_label(email.suggested_category)}
                class="badge badge-outline"
              >
                {category_label(email.suggested_category)}
              </span>
              <span class={["badge", status_badge_class(email.status)]}>{email.status}</span>
            </div>
            <span class="text-xs text-base-content/60">
              {email.from_name} &lt;{email.from_email}&gt;
            </span>
          </div>

          <p class="mt-2 text-sm font-semibold">{email.subject}</p>
          <p class="mt-1 whitespace-pre-wrap text-sm text-base-content/70">{email.body}</p>

          <form
            :if={email.status == "pending"}
            id={"inbound-email-form-#{email.id}"}
            phx-change="update_draft_reply"
            phx-value-id={email.id}
            class="mt-3"
          >
            <textarea
              name="draft_reply"
              rows="4"
              class="textarea textarea-bordered w-full"
              placeholder="AI draft unavailable - write a reply"
              phx-debounce="500"
            >{email.draft_reply}</textarea>
          </form>

          <p :if={email.status != "pending"} class="mt-3 whitespace-pre-wrap text-sm">
            {email.draft_reply}
          </p>

          <p :if={email.status == "failed"} class="mt-2 text-sm text-error">
            {email.error}
          </p>

          <p :if={email.status == "sent"} class="mt-2 text-xs text-base-content/60">
            Sent {email.sent_at}
          </p>

          <div :if={email.status == "pending"} class="mt-3 flex gap-2">
            <button
              phx-click="approve"
              phx-value-id={email.id}
              id={"approve-inbound-email-#{email.id}"}
              class="btn btn-sm btn-primary"
              disabled={is_nil(email.draft_reply) or String.trim(email.draft_reply || "") == ""}
              data-confirm={"Send this reply to #{email.from_email}? This can't be undone."}
            >
              Approve &amp; send
            </button>
            <button
              phx-click="reject"
              phx-value-id={email.id}
              id={"reject-inbound-email-#{email.id}"}
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
