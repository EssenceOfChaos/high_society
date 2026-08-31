defmodule HighSociety.PokerFixtures do
  @moduledoc """
  Test helpers for Poker. Unlike most of the app, Poker's tables are
  long-lived GenServers started once as part of the OTP supervision tree,
  not per-request/per-test state - the Ecto Sandbox rolls back what a test
  wrote to the database, but it can't reset a table's in-memory seats or
  in-progress hand left over from a previous test. `reset_table!/1` stops
  the named table (its `:permanent` restart type means the supervisor
  immediately starts a fresh one in its place) so every test starts from
  an empty table regardless of run order.

  Resetting only in `setup` isn't enough on its own: a test that deals a
  hand leaves a real, still-scheduled `Process.send_after` timer running
  (the 20s action clock, or the 4s between-hands pause) against a table
  process that outlives the test itself. If that timer fires later, mid
  some *other* test, it tries to persist through whatever Ecto Sandbox
  connection happens to be checked out at that moment - one that was
  never checked out on this process's behalf - which corrupts the shared
  connection for the whole suite, not just this test. `reset_table!/1`
  called again in `on_exit` (see `reset_table_around_test!/1`) kills that
  timer, along with the process it belonged to, before the test's own
  sandbox connection goes away.
  """

  alias HighSociety.Games.PokerTable

  @doc "Resets `slug` now, and again after the current test via `on_exit`."
  @spec reset_table_around_test!(String.t()) :: :ok
  def reset_table_around_test!(slug) do
    reset_table!(slug)
    ExUnit.Callbacks.on_exit(fn -> reset_table!(slug) end)
  end

  @spec reset_table!(String.t()) :: :ok
  def reset_table!(slug) do
    case GenServer.whereis(PokerTable.via(slug)) do
      nil ->
        :ok

      pid ->
        ref = Process.monitor(pid)
        GenServer.stop(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          1000 -> raise "poker table #{slug} did not stop within 1s"
        end
    end

    wait_until_ready(slug)
    :ok
  end

  # A `:via` name gets registered as the replacement process starts up,
  # before its own `init/1` runs - so seeing the name alone doesn't mean
  # the process has actually finished loading its state. `get_state/1` is
  # a synchronous `GenServer.call`, which can't complete until `init/1`
  # has returned, so waiting on it (rather than just the name) is what
  # actually guarantees the process is done before this test's caller
  # moves on - otherwise `init/1`'s own `Repo` call can end up racing
  # this test's sandbox connection being torn down right underneath it.
  defp wait_until_ready(slug) do
    if is_nil(GenServer.whereis(PokerTable.via(slug))) do
      Process.sleep(5)
      wait_until_ready(slug)
    else
      PokerTable.get_state(slug)
    end
  end
end
