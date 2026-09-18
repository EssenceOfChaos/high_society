defmodule HighSociety.Webhooks.SvixSignature do
  @moduledoc """
  Verifies webhooks signed the way [Svix](https://docs.svix.com) does, which
  Resend uses for all of its webhooks (`svix-id`/`svix-timestamp`/
  `svix-signature` headers) - see
  https://docs.svix.com/receiving/verifying-payloads/how-manual.

  HMAC-SHA256 over `"{id}.{timestamp}.{raw_body}"`, keyed by the base64
  portion of the `whsec_...` signing secret, base64-encoded and compared
  against the (possibly multiple, space-separated) `v1,...` values in the
  signature header. A timestamp tolerance guards against replaying an old,
  otherwise-still-validly-signed request.
  """

  @tolerance_seconds 300

  @doc """
  `secret` is the raw `whsec_...` signing secret from the provider's
  dashboard. `headers` is a map with string keys `"svix-id"`,
  `"svix-timestamp"`, `"svix-signature"` (however the caller pulls those
  out of the request). `raw_body` must be the exact bytes that were signed,
  before any JSON decoding.
  """
  def verify(secret, raw_body, headers) do
    with {:ok, id} <- fetch_header(headers, "svix-id"),
         {:ok, timestamp} <- fetch_header(headers, "svix-timestamp"),
         {:ok, signature_header} <- fetch_header(headers, "svix-signature"),
         :ok <- verify_timestamp(timestamp) do
      verify_signature(secret, raw_body, id, timestamp, signature_header)
    end
  end

  defp fetch_header(headers, key) do
    case Map.fetch(headers, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :missing_header}
    end
  end

  defp verify_timestamp(timestamp) do
    with {ts, ""} <- Integer.parse(timestamp),
         true <- abs(System.system_time(:second) - ts) <= @tolerance_seconds do
      :ok
    else
      _ -> {:error, :timestamp_out_of_tolerance}
    end
  end

  defp verify_signature(secret, raw_body, id, timestamp, signature_header) do
    key = secret |> String.trim_leading("whsec_") |> Base.decode64!()
    signed_content = "#{id}.#{timestamp}.#{raw_body}"
    expected = :crypto.mac(:hmac, :sha256, key, signed_content) |> Base.encode64()

    valid? =
      signature_header
      |> String.split(" ", trim: true)
      |> Enum.any?(fn versioned ->
        case String.split(versioned, ",", parts: 2) do
          ["v1", sig] -> Plug.Crypto.secure_compare(sig, expected)
          _ -> false
        end
      end)

    if valid?, do: :ok, else: {:error, :invalid_signature}
  end
end
