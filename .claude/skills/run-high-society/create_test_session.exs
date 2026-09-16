alias HighSociety.Accounts
alias HighSociety.Accounts.{User, UserToken}
alias HighSociety.Repo

# Registers (or reuses) a confirmed test user and mints a magic-link
# login token directly via UserToken.build_email_token/2, bypassing
# UserNotifier/Swoosh entirely - no email is sent or needs to be read.
# Usage: mix run create_test_session.exs [email]
email = System.argv() |> List.first() || "agent-test@example.com"

user =
  case Repo.get_by(User, email: email) do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: email})
      user

    user ->
      user
  end

{encoded_token, user_token} = UserToken.build_email_token(user, "login")
Repo.insert!(user_token)

port = Application.get_env(:high_society, HighSocietyWeb.Endpoint)[:http][:port] || 4000

IO.puts("EMAIL=#{user.email}")
IO.puts("LOGIN_URL=http://localhost:#{port}/users/log-in/#{encoded_token}")
