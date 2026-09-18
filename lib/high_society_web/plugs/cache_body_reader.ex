defmodule HighSocietyWeb.Plugs.CacheBodyReader do
  @moduledoc """
  A `Plug.Parsers` `:body_reader` that stashes the raw request body in
  `conn.assigns.raw_body` before it's consumed and parsed. Webhook signature
  verification (see `HighSociety.Webhooks.SvixSignature`, used by
  `HighSocietyWeb.ResendWebhookController`) has to hash the exact bytes the
  sender signed - by the time a controller sees `conn.body_params`, the raw
  body is already gone, so there's no other point to capture it from.

  Installed endpoint-wide (see `HighSocietyWeb.Endpoint`) rather than scoped
  to just the webhook route, since `Plug.Parsers` runs once for every
  request before routing decides which controller handles it. The app has
  no file uploads going through this parser (LiveView uploads go over the
  socket instead), so the extra copy this holds onto per request is small.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, stash(conn, body)}

      {:more, partial, conn} ->
        {:more, partial, stash(conn, partial)}

      {:error, _reason} = error ->
        error
    end
  end

  defp stash(conn, chunk) do
    update_in(conn.assigns[:raw_body], fn existing -> [chunk | List.wrap(existing)] end)
  end
end
