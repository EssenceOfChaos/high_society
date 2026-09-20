defmodule HighSocietyWeb.AdminThreadsController do
  @moduledoc """
  The admin-only OAuth handshake that connects `@High_Societycc`'s Threads
  account (see `HighSociety.Social.ThreadsClient`) - a plain controller
  since Meta calls back with a real HTTP redirect, not a LiveView socket.
  Mirrors `AdminTokenTransactionsController`'s admin gate
  (`Accounts.admin?/1`), since there's no plug-based equivalent of the
  `:require_admin` on_mount for controller actions.
  """
  use HighSocietyWeb, :controller

  alias HighSociety.Accounts
  alias HighSociety.Social
  alias HighSociety.Social.ThreadsClient

  def connect(conn, _params) do
    if_admin(conn, fn conn ->
      redirect(conn, external: ThreadsClient.authorize_url())
    end)
  end

  def callback(conn, %{"code" => code}) do
    if_admin(conn, fn conn ->
      with {:ok, %{access_token: short_lived, threads_user_id: threads_user_id}} <-
             ThreadsClient.exchange_code(code),
           {:ok, %{access_token: long_lived, expires_in: expires_in}} <-
             ThreadsClient.exchange_long_lived_token(short_lived) do
        expires_at = DateTime.add(DateTime.utc_now(:second), expires_in, :second)
        Social.connect_threads!(threads_user_id, long_lived, expires_at)

        conn
        |> put_flash(:info, "Threads connected.")
        |> redirect(to: ~p"/admin/social-posts")
      else
        {:error, reason} ->
          conn
          |> put_flash(:error, "Couldn't connect Threads: #{inspect(reason)}")
          |> redirect(to: ~p"/admin/social-posts")
      end
    end)
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Threads authorization was cancelled or denied.")
    |> redirect(to: ~p"/admin/social-posts")
  end

  defp if_admin(conn, fun) do
    if Accounts.admin?(conn.assigns.current_scope.user) do
      fun.(conn)
    else
      conn
      |> put_status(:forbidden)
      |> text("You don't have access to that page.")
    end
  end
end
