defmodule HighSociety.Accounts.Auth do
  alias HighSociety.Accounts.{User, Encryption}

  def login(params, repo) do
    user = repo.get_by(User, email: String.downcase(params["email"]))
    case authenticate(user, params["password"]) do
      true -> {:ok, user}
      _    -> :error
    end
  end

  defp authenticate(user, password) do
    case user do
      nil -> false
      _   -> Encryption.validate_password(password, user.password_hash)
    end
  end


  ## Helper functions for view
  def current_user(conn) do
    id = Plug.Conn.get_session(conn, :user_id)
    if id, do: HighSociety.Repo.get(User, id)
  end
  
  def logged_in?(conn), do: !!current_user(conn)
  
end