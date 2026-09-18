defmodule HighSocietyWeb.ResendWebhookController do
  @moduledoc """
  Receives Resend's `email.received` webhook for the `users.highsociety.cc`
  inbound domain and forwards it into `HighSociety.Support`. See
  `HighSociety.Webhooks.SvixSignature` for how the request is verified, and
  `HighSocietyWeb.Plugs.CacheBodyReader` (installed in the endpoint) for
  where the raw body this needs actually comes from.
  """
  use HighSocietyWeb, :controller

  require Logger

  alias HighSociety.Resend
  alias HighSociety.Support
  alias HighSociety.Webhooks.SvixSignature

  def create(conn, params) do
    secret = Application.fetch_env!(:high_society, :resend_webhook_secret)

    case SvixSignature.verify(secret, raw_body(conn), svix_headers(conn)) do
      :ok ->
        handle_event(params)
        send_resp(conn, 200, "")

      {:error, reason} ->
        Logger.warning("Rejected Resend webhook: #{inspect(reason)}")
        send_resp(conn, 401, "")
    end
  end

  defp handle_event(%{"type" => "email.received", "data" => %{"email_id" => email_id}}) do
    # The webhook payload itself is metadata only (no body) - fetch the
    # full email before there's anything worth forwarding to support.
    case Resend.fetch_received_email(email_id) do
      {:ok, email} ->
        Support.receive_inbound_email(email)

      {:error, reason} ->
        Logger.error("Failed to fetch received email #{email_id}: #{inspect(reason)}")
    end
  end

  defp handle_event(%{"type" => type}) do
    # Other event types (delivered/opened/bounced/...) aren't wired to
    # anything yet - ack them so Resend doesn't retry, just don't act on them.
    Logger.debug("Ignoring Resend webhook event: #{type}")
  end

  defp raw_body(conn) do
    conn.assigns |> Map.get(:raw_body, []) |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp svix_headers(conn) do
    for name <- ~w(svix-id svix-timestamp svix-signature), into: %{} do
      {name, conn |> get_req_header(name) |> List.first()}
    end
  end
end
