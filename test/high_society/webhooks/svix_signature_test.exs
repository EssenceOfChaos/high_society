defmodule HighSociety.Webhooks.SvixSignatureTest do
  use ExUnit.Case, async: true

  alias HighSociety.Webhooks.SvixSignature

  # From Svix's own worked example -
  # https://docs.svix.com/receiving/verifying-payloads/how-manual - a fixed
  # signature computed from a fixed secret/id/timestamp/payload, so this
  # confirms the algorithm itself (HMAC-SHA256, key/content construction)
  # matches what Resend's webhooks are actually signed with, independent of
  # this test's own signing helper below.
  test "verifies Svix's own documented example" do
    secret = "whsec_plJ3nmyCDGBKInavdOK15jsl"
    id = "msg_loFOjxBNrRLzqYUf"
    timestamp = "1731705121"
    payload = ~s({"event_type":"ping","data":{"success":true}})
    signature = "v1,rAvfW3dJ/X/qxhsaXPOyyCGmRKsaKWcsNccKXlIktD0="

    # The example's timestamp is long past, so this only checks the
    # signature math, not the freshness/tolerance check.
    headers = %{"svix-id" => id, "svix-timestamp" => timestamp, "svix-signature" => signature}
    key = secret |> String.trim_leading("whsec_") |> Base.decode64!()
    signed_content = "#{id}.#{timestamp}.#{payload}"
    expected = :crypto.mac(:hmac, :sha256, key, signed_content) |> Base.encode64()

    assert "v1," <> expected == signature
    assert {:error, :timestamp_out_of_tolerance} = SvixSignature.verify(secret, payload, headers)
  end

  describe "verify/3" do
    setup do
      %{secret: "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw", body: ~s({"hello":"world"})}
    end

    test "accepts a correctly signed, fresh request", %{secret: secret, body: body} do
      assert :ok = SvixSignature.verify(secret, body, sign(secret, body))
    end

    test "accepts whichever signature matches when the header lists several",
         %{secret: secret, body: body} do
      headers = sign(secret, body)
      multi = Map.update!(headers, "svix-signature", &"v1,not-it #{&1}")

      assert :ok = SvixSignature.verify(secret, body, multi)
    end

    test "rejects a tampered body", %{secret: secret, body: body} do
      headers = sign(secret, body)

      assert {:error, :invalid_signature} =
               SvixSignature.verify(secret, ~s({"hello":"mallory"}), headers)
    end

    test "rejects the wrong secret", %{secret: secret, body: body} do
      headers = sign(secret, body)

      assert {:error, :invalid_signature} =
               SvixSignature.verify("whsec_" <> Base.encode64("wrong"), body, headers)
    end

    test "rejects a stale timestamp", %{secret: secret, body: body} do
      stale = System.system_time(:second) - 600
      headers = sign(secret, body, stale)

      assert {:error, :timestamp_out_of_tolerance} = SvixSignature.verify(secret, body, headers)
    end

    test "rejects a missing header", %{secret: secret, body: body} do
      headers = sign(secret, body) |> Map.delete("svix-signature")

      assert {:error, :missing_header} = SvixSignature.verify(secret, body, headers)
    end
  end

  defp sign(secret, body, timestamp \\ System.system_time(:second)) do
    id = "msg_test"
    key = secret |> String.trim_leading("whsec_") |> Base.decode64!()
    signed_content = "#{id}.#{timestamp}.#{body}"
    signature = :crypto.mac(:hmac, :sha256, key, signed_content) |> Base.encode64()

    %{
      "svix-id" => id,
      "svix-timestamp" => to_string(timestamp),
      "svix-signature" => "v1,#{signature}"
    }
  end
end
