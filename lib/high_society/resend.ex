defmodule HighSociety.Resend do
  @moduledoc """
  Thin client for the one part of Resend's REST API this app calls
  directly, as opposed to sending mail (which goes through Swoosh's Resend
  adapter - see `HighSociety.Mailer`): fetching the full body of an email
  received via the inbound webhook. The `email.received` webhook payload
  itself is metadata only ("Webhooks do not include the email body,
  headers, or attachments, only their metadata" - Resend's docs), so
  `HighSocietyWeb.ResendWebhookController` has to make this call to get
  anything worth forwarding to support.
  """

  @doc """
  Fetches a received email's full body/headers by its `email_id` (from the
  `email.received` webhook payload's `data.email_id`). See
  https://resend.com/docs/api-reference/emails/retrieve-received-email.

  Returns `{:ok, body}` with the decoded JSON response (has `"from"`,
  `"subject"`, `"text"`, `"html"`, ...) or `{:error, reason}`.
  """
  def fetch_received_email(email_id) do
    case Req.get(req(), url: "/emails/receiving/#{email_id}") do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {status, body}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp req do
    Req.new(
      [base_url: "https://api.resend.com", auth: {:bearer, api_key()}] ++
        Application.get_env(:high_society, __MODULE__, [])
    )
  end

  defp api_key, do: Application.fetch_env!(:high_society, :resend_api_key)
end
