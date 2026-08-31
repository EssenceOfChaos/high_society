defmodule HighSociety.Games.PokerBots do
  @moduledoc """
  Dev-only convenience, off everywhere else (`enabled?/0` is backed by
  `config :high_society, :poker_bots_enabled`, `true` only in
  `config/dev.exs`): seats two bot accounts at the New York table so
  there's always a live game to look at locally without needing a second
  real browser session, and makes each one act on its own turn - check if
  it can, otherwise call or fold, chosen at random, after a short
  "thinking" pause - so the table plays itself instead of sitting idle.

  Every entry point here is safe to call unconditionally from production
  code paths (`HighSociety.Games.PokerTable` does exactly that): each one
  checks `enabled?/0` first and is a no-op otherwise, so this module has
  zero effect outside `:dev`.
  """

  alias HighSociety.Accounts
  alias HighSociety.Games.PokerTable

  @bots [
    %{email: "bot-alice@example.com", seat: 0},
    %{email: "bot-bob@example.com", seat: 1}
  ]
  @starting_balance 100_000
  @buy_in 200
  @table_slug "new-york"
  @min_think_ms 800
  @max_think_ms 2_500

  @doc "Whether the dev poker bots are turned on."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:high_society, :poker_bots_enabled, false)

  @doc "Whether `user_id` belongs to one of the dev bot accounts."
  @spec bot?(pos_integer()) :: boolean()
  def bot?(user_id), do: enabled?() and user_id in bot_user_ids()

  @doc "A random delay (ms) before a bot acts, so it doesn't act instantly."
  @spec think_time_ms() :: pos_integer()
  def think_time_ms, do: Enum.random(@min_think_ms..@max_think_ms)

  @doc "Picks a random action for a bot on the clock, weighted to keep the game moving."
  @spec choose_action(boolean()) :: :check | :call | :fold
  def choose_action(can_check?) do
    if can_check?,
      do: Enum.random([:check, :check, :check, :check, :fold]),
      else: Enum.random([:call, :call, :call, :fold])
  end

  @doc """
  Ensures both bot accounts exist and are seated at the table. Safe to
  call repeatedly (at boot, and after every table update): sitting down
  is a no-op once a bot is already seated, so this is what re-seats a bot
  that busted out (stack hit zero, auto-standing it per the table's own
  rules) with a fresh buy-in.
  """
  @spec maintain!() :: :ok
  def maintain! do
    if enabled?(), do: Enum.each(@bots, &ensure_seated!/1)
    :ok
  end

  defp ensure_seated!(%{email: email, seat: seat}) do
    user = ensure_user!(email)

    case PokerTable.sit(@table_slug, user, seat, @buy_in) do
      {:ok, _view} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp ensure_user!(email) do
    case Accounts.get_user_by_email(email) do
      nil -> create_user!(email)
      user -> user
    end
  end

  # `maintain!/0` runs from a fresh, unsupervised Task after every table
  # update (see `finalize/1` in `PokerTable`) as well as once at boot, so
  # two calls can both see no user yet and both try to create one - the
  # loser hits the unique email constraint here instead of crashing, and
  # just uses whichever row the winner created.
  defp create_user!(email) do
    case Accounts.register_user(%{email: email}) do
      {:ok, user} ->
        {:ok, user} = Accounts.adjust_balance(user, @starting_balance)
        user

      {:error, %Ecto.Changeset{}} ->
        Accounts.get_user_by_email(email)
    end
  end

  defp bot_user_ids do
    @bots
    |> Enum.map(&Accounts.get_user_by_email(&1.email))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.id)
  end
end
