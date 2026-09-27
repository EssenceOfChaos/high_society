defmodule HighSociety.Support do
  @moduledoc """
  Handles support reports submitted from the site and emails them to the
  support inbox, plus the AI-drafted review queue for emails received at
  the inbound domain (see `receive_inbound_email/1` and
  `HighSociety.Support.InboundEmail`).
  """

  import Ecto.Query
  require Logger

  alias HighSociety.Repo
  alias HighSociety.Mailer
  alias HighSociety.Support.{ClaudeClient, InboundEmail, Notifier, Report}

  @topic "inbound_emails"

  @doc "The PubSub topic new inbound-email drafts and status changes are broadcast on."
  def topic, do: @topic

  @doc """
  Returns a changeset for tracking report changes.
  """
  def change_report(%Report{} = report, attrs \\ %{}) do
    Report.changeset(report, attrs)
  end

  @doc """
  Validates and delivers a support report to the support inbox.
  """
  def send_report(attrs) do
    with {:ok, report} <- Report.changeset(%Report{}, attrs) |> Ecto.Changeset.apply_action(:save) do
      Notifier.deliver_report(report)
    end
  end

  @doc """
  Turns an email received at the `mail.highsociety.cc` inbound domain (via
  `HighSocietyWeb.ResendWebhookController`) into a support report, the same
  as one submitted through the site's form - forwarded to the support inbox
  with reply-to set to whoever sent it in, so replying goes straight back to
  them without round-tripping through this app.

  Also persists an `InboundEmail` row and asks `ClaudeClient` to draft a
  suggested category/reply for it, for an admin to review, edit, and
  approve (which sends it) or reject at `/admin/inbound-emails`. A failed
  or malformed AI call still leaves the row behind with an empty draft
  rather than losing the email - see `ClaudeClient`'s moduledoc for why
  its output is never trusted beyond being a suggestion for that review.

  `data` is a received email as returned by `HighSociety.Resend.fetch_received_email/1`
  (the `email.received` webhook payload itself only carries metadata, not
  the body - see that module's docs).
  """
  def receive_inbound_email(%{"from" => from} = data) do
    {name, email} = parse_from_header(from)
    subject = data["subject"] || "(no subject)"
    body = data["text"] || strip_html(data["html"]) || "(no message body)"

    result =
      send_report(%{
        "name" => name,
        "email" => email,
        "category" => "email",
        "message" => String.slice("Subject: #{subject}\n\n#{body}", 0, 4000)
      })

    create_inbound_email(name, email, subject, body)

    result
  end

  @doc "Lists inbound-email drafts, most recently received first."
  def list_inbound_emails(limit \\ 100) do
    InboundEmail
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Edits a still-pending draft's reply before it's approved."
  def update_draft_reply(%InboundEmail{status: "pending"} = inbound_email, draft_reply) do
    inbound_email
    |> InboundEmail.reply_changeset(%{draft_reply: draft_reply})
    |> Repo.update()
  end

  @doc "Approves a pending draft and emails the reply to the original sender immediately."
  def approve_and_send!(%InboundEmail{status: "pending"} = inbound_email, reviewer) do
    inbound_email =
      inbound_email
      |> InboundEmail.reviewed_changeset(%{status: "approved", reviewed_by_user_id: reviewer.id})
      |> Repo.update!()
      |> send_reply!()

    broadcast({:inbound_email_updated, inbound_email})
    inbound_email
  end

  @doc "Rejects a pending draft - it's never sent."
  def reject!(%InboundEmail{status: "pending"} = inbound_email, reviewer) do
    inbound_email =
      inbound_email
      |> InboundEmail.reviewed_changeset(%{status: "rejected", reviewed_by_user_id: reviewer.id})
      |> Repo.update!()

    broadcast({:inbound_email_updated, inbound_email})
    inbound_email
  end

  defp create_inbound_email(name, email, subject, body) do
    {:ok, inbound_email} =
      %InboundEmail{}
      |> InboundEmail.create_changeset(%{
        from_name: name,
        from_email: email,
        subject: subject,
        body: body
      })
      |> Repo.insert()

    inbound_email =
      case ClaudeClient.draft_reply(%{from: "#{name} <#{email}>", subject: subject, body: body}) do
        {:ok, %{category: category, reply: reply}} ->
          inbound_email
          |> InboundEmail.draft_changeset(%{suggested_category: category, draft_reply: reply})
          |> Repo.update!()

        {:error, reason} ->
          Logger.error(
            "Failed to draft AI reply for inbound email #{inbound_email.id}: #{inspect(reason)}"
          )

          inbound_email
      end

    broadcast({:inbound_email_created, inbound_email})
    inbound_email
  end

  defp send_reply!(%InboundEmail{} = inbound_email) do
    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(inbound_email.from_email)
      |> Swoosh.Email.from(
        {"High Society Support", Application.get_env(:high_society, :mailer_from_email)}
      )
      |> Swoosh.Email.subject("Re: #{inbound_email.subject}")
      |> Swoosh.Email.text_body(inbound_email.draft_reply)

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        inbound_email
        |> InboundEmail.sent_changeset(%{status: "sent", sent_at: DateTime.utc_now(:second)})
        |> Repo.update!()

      {:error, reason} ->
        inbound_email
        |> InboundEmail.sent_changeset(%{status: "failed", error: inspect(reason)})
        |> Repo.update!()
    end
  end

  # Resend's "from" is either a plain address or a `Name <email>` display
  # form (RFC 5322) - fall back to using the address itself as the name
  # when there's no display name to pull out.
  defp parse_from_header(from) do
    case Regex.run(~r/^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$/, from) do
      [_, "", email] -> {email, email}
      [_, name, email] -> {name, email}
      nil -> {from, from}
    end
  end

  defp strip_html(nil), do: nil
  defp strip_html(html), do: html |> String.replace(~r/<[^>]*>/, " ") |> String.trim()

  defp broadcast(message), do: Phoenix.PubSub.broadcast(HighSociety.PubSub, @topic, message)
end
