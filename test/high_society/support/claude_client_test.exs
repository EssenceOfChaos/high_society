defmodule HighSociety.Support.ClaudeClientTest do
  use ExUnit.Case, async: true

  alias HighSociety.Support.ClaudeClient

  @email %{from: "Ada Lovelace <ada@example.com>", subject: "Question", body: "Hello there"}

  test "sends the email as untrusted data and parses a valid JSON draft" do
    Req.Test.stub(ClaudeClient, fn conn ->
      assert conn.request_path == "/v1/messages"
      assert ["test_anthropic_api_key"] = Plug.Conn.get_req_header(conn, "x-api-key")
      assert ["2023-06-01"] = Plug.Conn.get_req_header(conn, "anthropic-version")

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["system"] =~ "DATA ONLY"
      assert Enum.any?(decoded["messages"], fn m -> m["content"] =~ "Hello there" end)

      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "text", "text" => ~s({"category": "bug", "reply": "Thanks, we're on it."})}
        ]
      })
    end)

    assert {:ok, %{category: "bug", reply: "Thanks, we're on it."}} =
             ClaudeClient.draft_reply(@email)
  end

  test "tolerates the model wrapping the JSON in a markdown fence" do
    Req.Test.stub(ClaudeClient, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{
            "type" => "text",
            "text" => "```json\n{\"category\": \"other\", \"reply\": \"Hi!\"}\n```"
          }
        ]
      })
    end)

    assert {:ok, %{category: "other", reply: "Hi!"}} = ClaudeClient.draft_reply(@email)
  end

  test "returns an error for a non-JSON response" do
    Req.Test.stub(ClaudeClient, fn conn ->
      Req.Test.json(conn, %{
        "content" => [%{"type" => "text", "text" => "I can't help with that."}]
      })
    end)

    assert {:error, :bad_response} = ClaudeClient.draft_reply(@email)
  end

  test "returns an error for an unrecognized category" do
    Req.Test.stub(ClaudeClient, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{"type" => "text", "text" => ~s({"category": "not_a_real_category", "reply": "Hi!"})}
        ]
      })
    end)

    assert {:error, :bad_response} = ClaudeClient.draft_reply(@email)
  end

  test "returns an error for a blank reply" do
    Req.Test.stub(ClaudeClient, fn conn ->
      Req.Test.json(conn, %{
        "content" => [%{"type" => "text", "text" => ~s({"category": "other", "reply": "  "})}]
      })
    end)

    assert {:error, :bad_response} = ClaudeClient.draft_reply(@email)
  end

  test "returns an error for a non-200 response" do
    Req.Test.stub(ClaudeClient, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, {500, "boom"}} = ClaudeClient.draft_reply(@email)
  end
end
