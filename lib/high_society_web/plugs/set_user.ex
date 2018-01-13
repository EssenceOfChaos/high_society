defmodule HighSocietyWeb.Plugs.SetUser do
  import Plug.Conn


  alias HighSociety.Repo
  alias HighSociety.Accounts.User

  def init(_params) do
  end

  def call(conn, _params) do
    if conn.assigns[:current_user] do
      conn
    else
      user_id = get_session(conn, :user_id)

      cond do
        user = user_id && Repo.get(User, user_id) ->
          assign(conn, :current_user, user)
        true ->
          assign(conn, :current_user, nil)
      end
    end
  end
end