defmodule HighSocietyWeb.ResendWebhookControllerTest do
  use HighSocietyWeb.ConnCase, async: true

  import Swoosh.TestAssertions

  @endpoint HighSocietyWeb.Endpoint

  test "a validly signed email.received event fetches the body and forwards it to support", %{
    conn: conn
  } do
    email_id = "56761188-7520-42d8-8898-ff6fc54ce618"

    # The webhook payload itself is metadata only - Resend's docs are
    # explicit that it carries no body, so the controller has to fetch the
    # full email by id (stubbed here) before there's anything to forward.
    Req.Test.stub(HighSociety.Resend, fn conn ->
      assert conn.request_path == "/emails/receiving/#{email_id}"
      assert ["Bearer " <> _] = Plug.Conn.get_req_header(conn, "authorization")

      Req.Test.json(conn, %{
        "from" => "Ada Lovelace <ada@example.com>",
        "to" => ["reply@users.highsociety.cc"],
        "subject" => "Question about the tournament",
        "text" => "Does the tournament run every week?",
        "html" => nil
      })
    end)

    body =
      Jason.encode!(%{
        "type" => "email.received",
        "data" => %{"email_id" => email_id, "from" => "ada@example.com"}
      })

    conn =
      conn
      |> put_signed_headers(body)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/resend/inbound", body)

    assert response(conn, 200)

    support_email = Application.get_env(:high_society, :support_email)
    assert_email_sent(to: support_email, reply_to: "ada@example.com")
  end

  test "a fetch failure is logged and still acknowledged, without forwarding anything", %{
    conn: conn
  } do
    email_id = "does-not-exist"
    Req.Test.stub(HighSociety.Resend, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    body =
      Jason.encode!(%{
        "type" => "email.received",
        "data" => %{"email_id" => email_id, "from" => "ada@example.com"}
      })

    conn =
      conn
      |> put_signed_headers(body)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/resend/inbound", body)

    assert response(conn, 200)
    refute_email_sent()
  end

  test "an unsigned request is rejected", %{conn: conn} do
    body = Jason.encode!(%{"type" => "email.received", "data" => %{"from" => "a@example.com"}})

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/resend/inbound", body)

    assert response(conn, 401)
    refute_email_sent()
  end

  test "a request signed with the wrong secret is rejected", %{conn: conn} do
    body = Jason.encode!(%{"type" => "email.received", "data" => %{"from" => "a@example.com"}})

    conn =
      conn
      |> put_signed_headers(body, "whsec_" <> Base.encode64("not-the-real-secret"))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/resend/inbound", body)

    assert response(conn, 401)
    refute_email_sent()
  end

  test "a tampered body is rejected even with otherwise-valid headers", %{conn: conn} do
    signed_body = Jason.encode!(%{"type" => "email.received", "data" => %{"from" => "a@x.com"}})
    headers = signing_headers(signed_body)
    tampered_body = Jason.encode!(%{"type" => "email.received", "data" => %{"from" => "b@x.com"}})

    conn =
      conn
      |> put_headers(headers)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/resend/inbound", tampered_body)

    assert response(conn, 401)
    refute_email_sent()
  end

  test "other event types are acknowledged without side effects", %{conn: conn} do
    body = Jason.encode!(%{"type" => "email.delivered", "data" => %{}})

    conn =
      conn
      |> put_signed_headers(body)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/resend/inbound", body)

    assert response(conn, 200)
    refute_email_sent()
  end

  defp put_signed_headers(conn, body, secret \\ nil) do
    put_headers(conn, signing_headers(body, secret))
  end

  defp signing_headers(body, secret \\ nil) do
    secret = secret || Application.fetch_env!(:high_society, :resend_webhook_secret)
    id = "msg_test"
    timestamp = to_string(System.system_time(:second))
    key = secret |> String.trim_leading("whsec_") |> Base.decode64!()
    signed_content = "#{id}.#{timestamp}.#{body}"
    signature = :crypto.mac(:hmac, :sha256, key, signed_content) |> Base.encode64()

    %{
      "svix-id" => id,
      "svix-timestamp" => timestamp,
      "svix-signature" => "v1,#{signature}"
    }
  end

  defp put_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {k, v}, conn -> put_req_header(conn, k, v) end)
  end
end
