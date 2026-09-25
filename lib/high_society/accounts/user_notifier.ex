defmodule HighSociety.Accounts.UserNotifier do
  import Swoosh.Email
  require Logger

  alias HighSociety.Mailer
  alias HighSociety.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"HighSociety", Application.get_env(:high_society, :mailer_from_email)})
      |> subject(subject)
      |> text_body(body)

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}

      {:error, reason} = error ->
        Logger.error(
          "Failed to deliver email #{inspect(subject)} to #{inspect(recipient)}: #{inspect(reason)}"
        )

        error
    end
  end

  # Same as `deliver/3`, but sends through a Resend dashboard Template
  # (see `priv/resend_templates/login.html` for the HTML pasted in when
  # creating it, and `Swoosh.Adapters.Resend`'s "Using Templates"
  # moduledoc section for how `template_key`'s id + `variables` become
  # the actual API request) whenever one's configured for `template_key` -
  # falling back to the plain-text `body` otherwise, so dev/test and any
  # environment before a template's been created in Resend still send a
  # readable email instead of a blank one no non-Resend adapter could
  # ever render from a template id alone.
  defp deliver_templated(recipient, subject, template_key, variables, body) do
    email =
      new()
      |> to(recipient)
      |> from({"HighSociety", Application.get_env(:high_society, :mailer_from_email)})
      |> subject(subject)

    email =
      case Keyword.get(Application.get_env(:high_society, :resend_templates, []), template_key) do
        nil ->
          text_body(email, body)

        template_id ->
          put_provider_option(email, :template, %{id: template_id, variables: variables})
      end

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}

      {:error, reason} = error ->
        Logger.error(
          "Failed to deliver email #{inspect(subject)} to #{inspect(recipient)}: #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver a welcome email after a user confirms their account for the first time.
  """
  def deliver_welcome_email(user) do
    deliver(user.email, "Welcome to HighSociety!", """

    ==============================

    Hi #{user.email},

    Welcome to HighSociety! Your account is confirmed and ready to go.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver_templated(
      user.email,
      "Log in instructions",
      :login,
      %{
        headline: "Welcome back",
        action_text: "log into your account",
        button_text: "Log In",
        login_url: url
      },
      """

      ==============================

      Hi #{user.email},

      You can log into your account by visiting the URL below:

      #{url}

      #{standalone_app_note()}

      If you didn't request this email, please ignore this.

      ==============================
      """
    )
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver_templated(
      user.email,
      "Confirmation instructions",
      :login,
      %{
        headline: "Confirm your account",
        action_text: "confirm your account",
        button_text: "Confirm Account",
        login_url: url
      },
      """

      ==============================

      Hi #{user.email},

      You can confirm your account by visiting the URL below:

      #{url}

      #{standalone_app_note()}

      If you didn't create an account with us, please ignore this.

      ==============================
      """
    )
  end

  # Using the app from an iPhone/iPad Home Screen icon means the link above
  # opens in Safari, not the installed app - Safari and a "standalone"
  # home-screen web app keep entirely separate storage on iOS, so signing
  # in through Safari doesn't carry over. The log-in page has a "Using the
  # app from your Home Screen?" paste-the-link fallback specifically for
  # this (see `HighSocietyWeb.UserLive.Login`'s `.StandaloneMagicLinkPaste`
  # hook) - worth a line here since a user hitting this has no way to know
  # that fallback exists without being told. The `login.html` Resend
  # template carries this same note as static copy in its own markup
  # (it doesn't vary by case the way `action_text`/`button_text` do), so
  # it isn't one of the template's variables - only the plain-text
  # fallback below needs it spelled out here.
  defp standalone_app_note do
    """
    Using the High Society app from your phone's Home Screen? This link will open in \
    Safari instead of the app - copy it instead of tapping it (press and hold, then \
    "Copy Link"), then open the app and paste it into the "Using the app from your Home \
    Screen?" box on the log in page.\
    """
  end
end
