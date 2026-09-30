defmodule HighSociety.SupportTest do
  use HighSociety.DataCase, async: true

  import Swoosh.TestAssertions
  import HighSociety.AccountsFixtures

  alias HighSociety.Support

  describe "send_report/1" do
    test "delivers a valid report to the support inbox, categorized in the subject and body" do
      attrs = %{
        "name" => "Ada Lovelace",
        "email" => "ada@example.com",
        "category" => "legal",
        "message" => "Requesting a copy of our data processing agreement."
      }

      assert {:ok, report} = Support.send_report(attrs)
      assert report.name == "Ada Lovelace"

      support_email = Application.get_env(:high_society, :support_email)

      assert_email_sent(fn email ->
        assert email.to == [{"", support_email}]
        assert email.reply_to == {"", "ada@example.com"}
        assert email.subject == "[Legal Inquiry] Ada Lovelace"
        assert email.text_body =~ "Category: Legal Inquiry"
      end)
    end

    test "a gaming report includes the chosen game in the subject and body" do
      attrs = %{
        "name" => "Ada Lovelace",
        "email" => "ada@example.com",
        "category" => "gaming",
        "game" => "poker",
        "message" => "The poker table won't let me fold."
      }

      assert {:ok, _report} = Support.send_report(attrs)

      assert_email_sent(fn email ->
        assert email.subject == "[Gaming / Poker] Ada Lovelace"
        assert email.text_body =~ "Category: Gaming"
        assert email.text_body =~ "Game: Poker"
      end)
    end

    test "a gaming report without a chosen game is rejected" do
      attrs = %{
        "name" => "Ada Lovelace",
        "email" => "ada@example.com",
        "category" => "gaming",
        "message" => "Something's wrong with a game."
      }

      assert {:error, changeset} = Support.send_report(attrs)
      assert %{game: ["can't be blank"]} = errors_on(changeset)
      refute_email_sent()
    end

    test "returns an error changeset and sends nothing for invalid attrs" do
      attrs = %{"name" => "", "email" => "not-an-email", "message" => "too short"}

      assert {:error, changeset} = Support.send_report(attrs)
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
      assert %{email: ["must be a valid email"]} = errors_on(changeset)
      assert %{category: ["can't be blank"]} = errors_on(changeset)

      refute_email_sent()
    end
  end

  describe "receive_inbound_email/1" do
    test "forwards an inbound email to the support inbox, reply-to the sender" do
      stub_claude_draft()

      data = %{
        "from" => "Ada Lovelace <ada@example.com>",
        "subject" => "Question about the tournament",
        "text" => "Does the tournament run every week?"
      }

      assert {:ok, report} = Support.receive_inbound_email(data)
      assert report.name == "Ada Lovelace"
      assert report.email == "ada@example.com"
      assert report.category == "email"
      assert report.message =~ "Question about the tournament"
      assert report.message =~ "Does the tournament run every week?"

      support_email = Application.get_env(:high_society, :support_email)

      assert_email_sent(fn email ->
        assert email.to == [{"", support_email}]
        assert email.reply_to == {"", "ada@example.com"}
        assert email.subject =~ "[Received by Email (Uncategorized)]"
      end)
    end

    test "falls back to the bare address when there's no display name" do
      stub_claude_draft()
      data = %{"from" => "ada@example.com", "text" => "hello there"}

      assert {:ok, report} = Support.receive_inbound_email(data)
      assert report.name == "ada@example.com"
      assert report.email == "ada@example.com"
    end

    test "falls back to stripped html when there's no plain-text body" do
      stub_claude_draft()
      data = %{"from" => "ada@example.com", "html" => "<p>Hello <b>there</b></p>"}

      assert {:ok, report} = Support.receive_inbound_email(data)
      assert report.message =~ "Hello  there"
    end

    test "also persists an InboundEmail draft with the AI-suggested category/reply" do
      stub_claude_draft()

      data = %{
        "from" => "Ada Lovelace <ada@example.com>",
        "subject" => "Question about the tournament",
        "text" => "Does the tournament run every week?"
      }

      Support.receive_inbound_email(data)

      assert [inbound_email] = Support.list_inbound_emails()
      assert inbound_email.from_name == "Ada Lovelace"
      assert inbound_email.from_email == "ada@example.com"
      assert inbound_email.subject == "Question about the tournament"
      assert inbound_email.body =~ "Does the tournament run every week?"
      assert inbound_email.status == "pending"
      assert inbound_email.suggested_category == "gaming"
      assert inbound_email.draft_reply == "Thanks for reaching out!"
    end

    test "still persists a draft with an empty AI reply when the AI call fails" do
      Req.Test.stub(HighSociety.Support.ClaudeClient, fn conn ->
        Plug.Conn.send_resp(conn, 500, "")
      end)

      data = %{"from" => "ada@example.com", "text" => "hello there"}

      Support.receive_inbound_email(data)

      assert [inbound_email] = Support.list_inbound_emails()
      assert inbound_email.status == "pending"
      assert inbound_email.suggested_category == nil
      assert inbound_email.draft_reply == nil
    end
  end

  describe "the inbound-email review queue" do
    setup do
      stub_claude_draft()

      data = %{
        "from" => "Ada Lovelace <ada@example.com>",
        "subject" => "Question about the tournament",
        "text" => "Does the tournament run every week?"
      }

      Support.receive_inbound_email(data)
      Phoenix.PubSub.subscribe(HighSociety.PubSub, Support.topic())

      [inbound_email] = Support.list_inbound_emails()
      reviewer = user_fixture()

      # Drain the raw-forward-to-support-inbox email `receive_inbound_email/1`
      # already sends (unchanged, existing behavior) and `user_fixture/0`'s
      # own login-instructions email, so neither is mistaken for the reply
      # email a test below sends/asserts on.
      flush_mailbox()

      %{inbound_email: inbound_email, reviewer: reviewer}
    end

    test "update_draft_reply/2 edits a pending draft's reply", %{inbound_email: inbound_email} do
      assert {:ok, updated} = Support.update_draft_reply(inbound_email, "Edited reply.")
      assert updated.draft_reply == "Edited reply."
    end

    test "approve_and_send!/2 emails the sender and marks the draft sent", %{
      inbound_email: inbound_email,
      reviewer: reviewer
    } do
      updated = Support.approve_and_send!(inbound_email, reviewer)

      assert updated.status == "sent"
      assert updated.sent_at != nil
      assert updated.reviewed_by_user_id == reviewer.id
      assert_received {:inbound_email_updated, ^updated}

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.subject == "Re: Question about the tournament"
        assert email.text_body == "Thanks for reaching out!"
      end)
    end

    test "reject!/2 marks the draft rejected without sending anything", %{
      inbound_email: inbound_email,
      reviewer: reviewer
    } do
      updated = Support.reject!(inbound_email, reviewer)

      assert updated.status == "rejected"
      assert updated.reviewed_by_user_id == reviewer.id
      assert_received {:inbound_email_updated, ^updated}
      refute_email_sent()
    end
  end

  defp flush_mailbox do
    receive do
      {:email, _} -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  defp stub_claude_draft do
    Req.Test.stub(HighSociety.Support.ClaudeClient, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{
            "type" => "text",
            "text" =>
              Jason.encode!(%{"category" => "gaming", "reply" => "Thanks for reaching out!"})
          }
        ]
      })
    end)
  end
end
