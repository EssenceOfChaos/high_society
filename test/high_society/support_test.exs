defmodule HighSociety.SupportTest do
  use HighSociety.DataCase, async: true

  import Swoosh.TestAssertions

  alias HighSociety.Support

  describe "send_report/1" do
    test "delivers a valid report to the support inbox" do
      attrs = %{
        "name" => "Ada Lovelace",
        "email" => "ada@example.com",
        "message" => "The poker table won't let me fold."
      }

      assert {:ok, report} = Support.send_report(attrs)
      assert report.name == "Ada Lovelace"

      support_email = Application.get_env(:high_society, :support_email)

      assert_email_sent(
        to: support_email,
        reply_to: "ada@example.com",
        subject: "New support request from Ada Lovelace"
      )
    end

    test "returns an error changeset and sends nothing for invalid attrs" do
      attrs = %{"name" => "", "email" => "not-an-email", "message" => "too short"}

      assert {:error, changeset} = Support.send_report(attrs)
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
      assert %{email: ["must be a valid email"]} = errors_on(changeset)

      refute_email_sent()
    end
  end
end
