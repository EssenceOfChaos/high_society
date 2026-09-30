defmodule HighSocietyWeb.AdminLive.InboundEmailsTest do
  use HighSocietyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias HighSociety.Support
  alias HighSociety.Support.InboundEmail

  setup :register_and_log_in_user
  # Approving a draft sends mail from inside the LiveView process, not the
  # test process - global mode routes that delivery back to the test
  # process instead of crashing the LiveView with an unhandled `{:email,
  # _}` message.
  setup :set_swoosh_global

  setup do
    previous = Application.get_env(:high_society, :admin_emails, [])
    on_exit(fn -> Application.put_env(:high_society, :admin_emails, previous) end)
    # Drain the account-confirmation/welcome emails `register_and_log_in_user`
    # just sent so neither is mistaken for a reply email later in the test.
    flush_mailbox()
    :ok
  end

  defp flush_mailbox do
    receive do
      {:email, _} -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  test "redirects a guest to the log-in page" do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/inbound-emails")
  end

  test "redirects a non-admin user away with a flash", %{conn: conn} do
    Application.put_env(:high_society, :admin_emails, [])

    assert {:error, redirect} = live(conn, ~p"/admin/inbound-emails")
    assert {:redirect, %{to: "/", flash: flash}} = redirect
    assert flash["error"] =~ "don't have access"
  end

  test "an admin can edit, then approve and send a pending draft", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])
    inbound_email = pending_email_fixture()

    {:ok, view, html} = live(conn, ~p"/admin/inbound-emails")
    assert html =~ inbound_email.subject
    assert html =~ inbound_email.draft_reply

    view
    |> form("#inbound-email-form-#{inbound_email.id}", %{"draft_reply" => "Edited reply!"})
    |> render_change()

    html =
      view
      |> element("#approve-inbound-email-#{inbound_email.id}")
      |> render_click()

    assert html =~ "Reply sent."
    assert html =~ "sent"

    updated = HighSociety.Repo.get!(InboundEmail, inbound_email.id)
    assert updated.status == "sent"
    assert updated.draft_reply == "Edited reply!"
    assert updated.reviewed_by_user_id == admin.id

    assert_email_sent(fn email ->
      assert email.to == [{"", inbound_email.from_email}]
      assert email.text_body == "Edited reply!"
    end)
  end

  test "an admin can reject a pending draft", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])
    inbound_email = pending_email_fixture()

    {:ok, view, _html} = live(conn, ~p"/admin/inbound-emails")

    html =
      view
      |> element("#reject-inbound-email-#{inbound_email.id}")
      |> render_click()

    assert html =~ "rejected"
    refute has_element?(view, "#approve-inbound-email-#{inbound_email.id}")
    refute_email_sent()

    updated = HighSociety.Repo.get!(InboundEmail, inbound_email.id)
    assert updated.status == "rejected"
    assert updated.reviewed_by_user_id == admin.id
  end

  test "live-updates when a new inbound email arrives elsewhere", %{conn: conn, user: admin} do
    Application.put_env(:high_society, :admin_emails, [admin.email])
    {:ok, view, html} = live(conn, ~p"/admin/inbound-emails")
    refute html =~ "A brand new question"

    Req.Test.stub(HighSociety.Support.ClaudeClient, fn conn ->
      Plug.Conn.send_resp(conn, 500, "")
    end)

    Support.receive_inbound_email(%{
      "from" => "ada@example.com",
      "subject" => "A brand new question",
      "text" => "Hello!"
    })

    assert render(view) =~ "A brand new question"
  end

  defp pending_email_fixture do
    {:ok, inbound_email} =
      %InboundEmail{}
      |> InboundEmail.create_changeset(%{
        from_name: "Ada Lovelace",
        from_email: "ada@example.com",
        subject: "Question about the tournament",
        body: "Does the tournament run every week?"
      })
      |> HighSociety.Repo.insert()

    {:ok, inbound_email} =
      InboundEmail.draft_changeset(inbound_email, %{
        suggested_category: "gaming",
        draft_reply: "Thanks for reaching out!"
      })
      |> HighSociety.Repo.update()

    inbound_email
  end
end
