defmodule HighSociety.BattleshipFixtures do
  @moduledoc """
  Test helpers for live Battleship matches. Unlike Poker's tables (one
  long-lived GenServer per fixed table, shared across the whole test
  suite - see `HighSociety.PokerFixtures`), each match is its own
  short-lived, dynamically-supervised process created fresh by whichever
  test needs it, so there's no shared state to reset between tests -
  just a defensive stop in `on_exit` so a still-running match doesn't
  linger past the end of its test.
  """

  alias HighSociety.Accounts
  alias HighSociety.Games.BattleshipMatch

  import HighSociety.AccountsFixtures

  @doc "A user with plenty of balance to wager with."
  @spec funded_user(pos_integer) :: Accounts.User.t()
  def funded_user(balance \\ 10_000) do
    user = user_fixture()
    {:ok, user} = Accounts.adjust_balance(user, balance)
    user
  end

  @doc "Creates a match for `creator` with `wager`, stopping it after the test."
  @spec create_match_for_test!(Accounts.User.t(), pos_integer) :: String.t()
  def create_match_for_test!(creator, wager \\ 50) do
    {:ok, slug} = BattleshipMatch.create(creator, wager)
    stop_match_after_test!(slug)
    slug
  end

  @doc "Stops `slug`'s match process (if any) after the current test."
  @spec stop_match_after_test!(String.t()) :: :ok
  def stop_match_after_test!(slug) do
    ExUnit.Callbacks.on_exit(fn ->
      case GenServer.whereis(BattleshipMatch.via(slug)) do
        nil -> :ok
        pid -> try_stop(pid)
      end
    end)
  end

  defp try_stop(pid) do
    GenServer.stop(pid)
  catch
    :exit, _ -> :ok
  end

  @doc "Places a complete random fleet for `user_id` in `slug` and locks it in."
  @spec ready_with_random_fleet!(String.t(), integer) :: map
  def ready_with_random_fleet!(slug, user_id) do
    {:ok, _view} = BattleshipMatch.randomize_fleet(slug, user_id)
    {:ok, view} = BattleshipMatch.ready_up(slug, user_id)
    view
  end
end
