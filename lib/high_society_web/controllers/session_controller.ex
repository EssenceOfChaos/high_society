defmodule HighSocietyWeb.SessionController do
  use HighSocietyWeb, :controller
  alias HighSociety.Accounts.Auth
  alias HighSociety.Repo

  action_fallback HighSociety.FallbackController


  def new(conn, _params) do
    render conn, "new.html"
  end

  def create(conn, session_params) do
    case Auth.login(session_params, Repo) do
      {:ok, user} ->
        conn
        |> assign(:current_user, user)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Logged in")
        |> redirect(to: "/")
        |> configure_session(renew: true)
      :error ->
        conn
        |> put_flash(:error, "Incorrect email or password")
        |> render("new.html")
    end
  end



  def delete(conn, _) do
    conn
    |> delete_session(:user_id)
    |> put_flash(:info, "Logged out")
    |> redirect(to: "/")
  end



end
