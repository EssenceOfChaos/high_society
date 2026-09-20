defmodule HighSociety.Social.ThreadsTokenRefresher do
  @moduledoc """
  Keeps the connected Threads account's long-lived token (see
  `HighSociety.Social.ThreadsConnection`) from expiring - Meta issues these
  valid for ~60 days, unlike X's OAuth 1.0a token which never expires.
  Wakes up once a day, and refreshes whenever the stored token is within
  `@refresh_within_days` of expiring. A no-op until an admin has connected
  a Threads account at all (see `HighSocietyWeb.AdminThreadsController`).
  """
  use GenServer

  require Logger

  alias HighSociety.Social

  @check_interval :timer.hours(24)
  @refresh_within_days 7

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    Process.set_label(:threads_token_refresher)
    {:ok, %{}, {:continue, :check}}
  end

  @impl true
  def handle_continue(:check, state), do: do_check(state)

  @impl true
  def handle_info(:check, state), do: do_check(state)

  defp do_check(state) do
    with %Social.ThreadsConnection{} = connection <- Social.current_threads_connection(),
         true <- due_for_refresh?(connection) do
      case Social.refresh_threads_connection!(connection) do
        {:error, reason} -> Logger.error("Threads token refresh failed: #{inspect(reason)}")
        _connection -> :ok
      end
    end

    Process.send_after(self(), :check, @check_interval)
    {:noreply, state}
  end

  defp due_for_refresh?(%Social.ThreadsConnection{expires_at: expires_at}) do
    DateTime.diff(expires_at, DateTime.utc_now(:second), :day) <= @refresh_within_days
  end
end
