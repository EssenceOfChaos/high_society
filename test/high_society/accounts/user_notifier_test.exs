defmodule HighSociety.Accounts.UserNotifierTest do
  use HighSociety.DataCase, async: false

  import HighSociety.AccountsFixtures
  import Swoosh.TestAssertions

  alias HighSociety.Accounts.UserNotifier

  # `resend_templates` is normally empty in test (see config/config.exs),
  # so `deliver_login_instructions/2` always falls back to its
  # plain-text body - each test below activates a template id only
  # right before its own explicit `UserNotifier` call, specifically to
  # catch the class of bug that motivated writing this file: Resend
  # matches a template's own `{{{PLACEHOLDER}}}` variables by name *and
  # case*, so a variables map built with the wrong casing sends
  # successfully, looks fine in every assertion that doesn't check the
  # keys themselves, and then silently renders each placeholder as its
  # configured fallback value in the actual email - see
  # `HighSociety.Accounts.UserNotifier`'s `deliver_templated/5`
  # moduledoc comment.
  #
  # Deliberately *not* activated for the whole test via a blanket
  # `setup` - `user_fixture/1` itself sends and parses a real
  # confirmation email to build a confirmed test user (see
  # `HighSociety.AccountsFixtures.extract_user_token/1`), which only
  # works against a plain-text body; activating the login template
  # before calling it breaks fixture setup, not the thing under test.
  setup do
    previous = Application.get_env(:high_society, :resend_templates, [])
    on_exit(fn -> Application.put_env(:high_society, :resend_templates, previous) end)
    :ok
  end

  describe "deliver_login_instructions/2 with a configured template" do
    test "a confirmed (returning) user's variables use the exact uppercase keys the template expects" do
      user = user_fixture()
      assert_email_sent(subject: "Confirmation instructions")
      assert_email_sent(subject: "Welcome to HighSociety!")

      Application.put_env(:high_society, :resend_templates, login: "test-login-template-id")
      UserNotifier.deliver_login_instructions(user, "https://highsociety.cc/users/log-in/abc123")

      assert_email_sent(fn email ->
        %{template: %{id: "test-login-template-id", variables: variables}} =
          email.provider_options

        variables == %{
          "HEADLINE" => "Welcome back",
          "ACTION_TEXT" => "log into your account",
          "BUTTON_TEXT" => "Log In",
          "LOGIN_URL" => "https://highsociety.cc/users/log-in/abc123"
        }
      end)
    end

    test "an unconfirmed (first-time) user's variables use the exact uppercase keys the template expects" do
      # No confirmation email to drain - `unconfirmed_user_fixture/1` is a
      # plain `Accounts.register_user/1` call, nothing sent yet.
      user = unconfirmed_user_fixture()

      Application.put_env(:high_society, :resend_templates, login: "test-login-template-id")
      UserNotifier.deliver_login_instructions(user, "https://highsociety.cc/users/log-in/xyz789")

      assert_email_sent(fn email ->
        %{template: %{id: "test-login-template-id", variables: variables}} =
          email.provider_options

        variables == %{
          "HEADLINE" => "Confirm your account",
          "ACTION_TEXT" => "confirm your account",
          "BUTTON_TEXT" => "Confirm Account",
          "LOGIN_URL" => "https://highsociety.cc/users/log-in/xyz789"
        }
      end)
    end

    test "sends no html_body or text_body alongside a template, per Swoosh.Adapters.Resend's requirement" do
      user = user_fixture()
      assert_email_sent(subject: "Confirmation instructions")
      assert_email_sent(subject: "Welcome to HighSociety!")

      Application.put_env(:high_society, :resend_templates, login: "test-login-template-id")
      UserNotifier.deliver_login_instructions(user, "https://highsociety.cc/users/log-in/abc123")

      assert_email_sent(fn email -> is_nil(email.html_body) and is_nil(email.text_body) end)
    end
  end

  describe "deliver_login_instructions/2 without a configured template" do
    test "falls back to the plain-text body" do
      user = user_fixture()
      assert_email_sent(subject: "Confirmation instructions")
      assert_email_sent(subject: "Welcome to HighSociety!")

      UserNotifier.deliver_login_instructions(user, "https://highsociety.cc/users/log-in/abc123")

      assert_email_sent(fn email ->
        is_nil(email.provider_options[:template]) and
          email.text_body =~ "https://highsociety.cc/users/log-in/abc123"
      end)
    end
  end
end
