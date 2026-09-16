defmodule HighSociety.Games.ZombieAttackContext do
  @moduledoc """
  Persistence and wagering for Zombie Attack. A dedicated module (rather
  than folding into `HighSociety.Games`, which stays scoped to War/
  Blackjack/Slots/Roulette's single-shot-per-action shape) since a match
  here is multi-checkpoint - like Battleship's dedicated
  `BattleshipContext`, just without a second player/AI turn to resolve.

  Only three things ever cross from client to server: starting a match,
  reporting a wave cleared, and reporting the match ending in a loss. The
  client owns the entire real-time simulation in between - see
  `HighSociety.Games.ZombieAttack`'s moduledoc for what that means for
  anti-cheat.
  """

  import Ecto.Query, warn: false

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Accounts.User
  alias HighSociety.Games.ZombieAttack
  alias HighSociety.Games.ZombieAttackGame
  alias HighSociety.Repo

  @doc "The current user's in-progress Zombie Attack game, or `nil`."
  @spec get_active_zombie_attack_game(Scope.t()) :: ZombieAttackGame.t() | nil
  def get_active_zombie_attack_game(%Scope{user: user}) do
    Repo.one(
      from zg in ZombieAttackGame,
        where: zg.user_id == ^user.id and zg.status == "in_progress"
    )
  end

  @doc """
  Starts a fresh match, debiting `wager` from the user's balance up front
  and generating the wave schedule the client will simulate. Discards any
  previous unresolved game for the user.
  """
  @spec start_zombie_attack_game(Scope.t(), pos_integer) ::
          {:ok, ZombieAttackGame.t()} | {:error, :insufficient_funds | :wager_too_high}
  def start_zombie_attack_game(%Scope{user: user}, wager)
      when is_integer(wager) and wager > 0 do
    if wager > ZombieAttack.max_wager() do
      {:error, :wager_too_high}
    else
      Repo.transact(fn ->
        with {:ok, _user} <- Accounts.adjust_tokens_balance(user, -wager, "zombie_attack_wager") do
          Repo.delete_all(
            from zg in ZombieAttackGame,
              where: zg.user_id == ^user.id and zg.status == "in_progress"
          )

          game =
            %ZombieAttackGame{}
            |> ZombieAttackGame.changeset(%{
              user_id: user.id,
              wager: wager,
              status: "in_progress",
              wave_reached: 0,
              wave_schedule: ZombieAttack.full_wave_schedule()
            })
            |> Repo.insert!()

          {:ok, game}
        end
      end)
    end
  end

  @doc """
  Records that the client cleared `wave_number`. Rejects anything other
  than the very next expected wave (see
  `HighSociety.Games.ZombieAttack.valid_next_wave?/2`). Clearing the final
  wave settles the match as a full-clear win right here, since there's
  nothing left for the player to lose to.
  """
  @spec report_wave_cleared(Scope.t(), ZombieAttackGame.t(), pos_integer) ::
          {:ok, ZombieAttackGame.t(), User.t()} | {:error, :invalid_checkpoint}
  def report_wave_cleared(%Scope{user: user}, %ZombieAttackGame{} = game, wave_number) do
    if ZombieAttack.valid_next_wave?(game.wave_reached, wave_number) do
      if wave_number == ZombieAttack.wave_count() do
        settle(user, game, wave_number, "won", ZombieAttack.payout_for(game.wager, :full_clear))
      else
        game =
          game
          |> ZombieAttackGame.changeset(%{wave_reached: wave_number})
          |> Repo.update!()

        {:ok, game, user}
      end
    else
      {:error, :invalid_checkpoint}
    end
  end

  @doc """
  Records that a zombie reached the house, ending the match in a loss.
  Payout is based on the highest wave already cleared - zero if the
  player lost during wave 1.
  """
  @spec report_game_over(Scope.t(), ZombieAttackGame.t()) :: {:ok, ZombieAttackGame.t(), User.t()}
  def report_game_over(%Scope{user: user}, %ZombieAttackGame{} = game) do
    payout = ZombieAttack.payout_for(game.wager, {:cleared_wave, game.wave_reached})
    settle(user, game, game.wave_reached, "lost", payout)
  end

  # `Accounts.get_user!/1` is used unconditionally below, rather than only
  # when crediting a payout, since the caller's `user` struct may be stale
  # (e.g. captured before a wager debit) - `adjust_tokens_balance/4` itself is
  # safe against that (its guard is computed in SQL against the current
  # row, not the passed-in struct), but a zero-payout settle wouldn't call
  # it at all, and would otherwise hand back that stale balance.
  defp settle(user, game, wave_reached, status, payout) do
    {:ok, {game, user}} =
      Repo.transact(fn ->
        {:ok, _user} =
          if payout > 0 do
            Accounts.adjust_tokens_balance(user, payout, "zombie_attack_payout", %{
              status: status,
              wave_reached: wave_reached
            })
          else
            {:ok, user}
          end

        user = Accounts.get_user!(user.id)

        game =
          game
          |> ZombieAttackGame.changeset(%{
            status: status,
            wave_reached: wave_reached,
            payout: payout
          })
          |> Repo.update!()

        {:ok, {game, user}}
      end)

    {:ok, game, user}
  end
end
