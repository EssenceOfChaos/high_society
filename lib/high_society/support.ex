defmodule HighSociety.Support do
  @moduledoc """
  Handles support reports submitted from the site and emails them to the
  support inbox.
  """

  alias HighSociety.Support.Report
  alias HighSociety.Support.Notifier

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
  Turns an email received at the `users.highsociety.cc` inbound domain (via
  `HighSocietyWeb.ResendWebhookController`) into a support report, the same
  as one submitted through the site's form - forwarded to the support inbox
  with reply-to set to whoever sent it in, so replying goes straight back to
  them without round-tripping through this app.

  `data` is a received email as returned by `HighSociety.Resend.fetch_received_email/1`
  (the `email.received` webhook payload itself only carries metadata, not
  the body - see that module's docs).
  """
  def receive_inbound_email(%{"from" => from} = data) do
    {name, email} = parse_from_header(from)
    subject = data["subject"] || "(no subject)"
    body = data["text"] || strip_html(data["html"]) || "(no message body)"

    send_report(%{
      "name" => name,
      "email" => email,
      "category" => "email",
      "message" => String.slice("Subject: #{subject}\n\n#{body}", 0, 4000)
    })
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
end
