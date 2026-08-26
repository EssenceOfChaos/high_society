defmodule HighSociety.Games do
  @moduledoc """
  The Games context. Owns persistence for the individual card games (starting
  with War) and translates between their pure game-logic structs and the
  Ecto schemas used to store game state in Postgres.
  """

  import Ecto.Query, warn: false

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Accounts.User
  alias HighSociety.Repo
  alias HighSociety.Games.Blackjack
  alias HighSociety.Games.BlackjackGame
  alias HighSociety.Games.War
  alias HighSociety.Games.WarGame

  @doc """
  Returns the current user's in-progress War game, or `nil` if they don't
  have one yet.
  """
  @spec get_active_war_game(Scope.t()) :: WarGame.t() | nil
  def get_active_war_game(%Scope{user: user}) do
    Repo.one(
      from wg in WarGame,
        where: wg.user_id == ^user.id and wg.status == "in_progress"
    )
  end

  @doc """
  Starts a brand new War game for the current user, discarding any
  previously in-progress game.
  """
  @spec start_war_game(Scope.t()) :: WarGame.t()
  def start_war_game(%Scope{user: user}) do
    Repo.delete_all(
      from wg in WarGame, where: wg.user_id == ^user.id and wg.status == "in_progress"
    )

    persist(user, War.new())
  end

  @doc """
  Plays a single round of War for the given persisted game and saves the
  resulting state back to the database.
  """
  @spec play_round(WarGame.t()) :: WarGame.t()
  def play_round(%WarGame{} = war_game) do
    war_game
    |> to_war()
    |> War.play_round()
    |> then(&save_round(war_game, &1))
  end

  defp to_war(%WarGame{} = war_game) do
    %War{
      player_deck: war_game.player_deck,
      computer_deck: war_game.computer_deck,
      status: String.to_existing_atom(war_game.status),
      last_round: atomize_last_round(war_game.last_round),
      war: atomize_war(war_game.pending_war)
    }
  end

  defp atomize_last_round(nil), do: nil

  defp atomize_last_round(%{} = last_round) do
    %{
      player_card: last_round["player_card"],
      computer_card: last_round["computer_card"],
      winner: last_round["winner"] && String.to_existing_atom(last_round["winner"]),
      war?: last_round["war?"],
      pending?: last_round["pending?"] || false,
      cards_won: last_round["cards_won"],
      ties: atomize_ties(last_round["ties"])
    }
  end

  defp atomize_war(nil), do: nil

  defp atomize_war(%{} = war) do
    %{pot: war["pot"], ties: atomize_ties(war["ties"])}
  end

  defp atomize_ties(nil), do: []

  defp atomize_ties(ties) do
    Enum.map(ties, fn tie ->
      %{player_card: tie["player_card"], computer_card: tie["computer_card"]}
    end)
  end

  defp persist(user, %War{} = war) do
    %WarGame{}
    |> WarGame.changeset(%{
      user_id: user.id,
      status: Atom.to_string(war.status),
      player_deck: war.player_deck,
      computer_deck: war.computer_deck,
      round_number: 0,
      last_round: stringify_last_round(war.last_round),
      pending_war: stringify_war(war.war)
    })
    |> Repo.insert!()
  end

  defp save_round(%WarGame{} = war_game, %War{} = war) do
    war_game
    |> WarGame.changeset(%{
      status: Atom.to_string(war.status),
      player_deck: war.player_deck,
      computer_deck: war.computer_deck,
      round_number: war_game.round_number + 1,
      last_round: stringify_last_round(war.last_round),
      pending_war: stringify_war(war.war)
    })
    |> Repo.update!()
  end

  defp stringify_last_round(nil), do: nil

  defp stringify_last_round(%{} = last_round) do
    %{
      "player_card" => last_round.player_card,
      "computer_card" => last_round.computer_card,
      "winner" => last_round.winner && Atom.to_string(last_round.winner),
      "war?" => last_round.war?,
      "pending?" => last_round.pending?,
      "cards_won" => last_round.cards_won,
      "ties" => stringify_ties(last_round.ties)
    }
  end

  defp stringify_war(nil), do: nil

  defp stringify_war(%{} = war) do
    %{"pot" => war.pot, "ties" => stringify_ties(war.ties)}
  end

  defp stringify_ties(ties) do
    Enum.map(ties, fn tie ->
      %{"player_card" => tie.player_card, "computer_card" => tie.computer_card}
    end)
  end

  ## Blackjack

  @doc """
  Returns the current user's most recent Blackjack round, or `nil` if
  they've never played one. Unlike `get_active_war_game/1`, this returns
  the latest row regardless of status (including `"round_over"`): because
  real money is debited the moment a round is dealt, a mid-round or
  just-finished round must be resumable on remount, not silently discarded.
  """
  @spec get_active_blackjack_game(Scope.t()) :: BlackjackGame.t() | nil
  def get_active_blackjack_game(%Scope{user: user}) do
    Repo.one(
      from bg in BlackjackGame,
        where: bg.user_id == ^user.id,
        order_by: [desc: bg.id],
        limit: 1
    )
  end

  @doc """
  Places bets on 1 or 2 boxes and deals a fresh Blackjack round, debiting
  the total bet from the user's balance. `bets` is a map of box (`0` and/or
  `1`) to a positive bet amount. Enforces the per-box max bet and available
  balance server-side, independent of anything the client sends. Discards
  any previous round for the user.
  """
  @spec start_blackjack_round(Scope.t(), %{optional(0) => pos_integer, optional(1) => pos_integer}) ::
          {:ok, BlackjackGame.t()} | {:error, :no_bets | :bet_too_large | :insufficient_funds}
  def start_blackjack_round(%Scope{user: user}, bets) do
    bets = bets |> Enum.reject(fn {_box, amount} -> amount <= 0 end) |> Map.new()

    cond do
      bets == %{} ->
        {:error, :no_bets}

      Enum.any?(bets, fn {_box, amount} -> amount > Blackjack.max_bet() end) ->
        {:error, :bet_too_large}

      true ->
        total = bets |> Map.values() |> Enum.sum()

        Repo.transact(fn ->
          with {:ok, _user} <- Accounts.adjust_balance(user, -total) do
            Repo.delete_all(from bg in BlackjackGame, where: bg.user_id == ^user.id)
            {:ok, persist_blackjack(user, Blackjack.new(bets))}
          end
        end)
    end
  end

  @doc """
  Hits the active hand of a persisted Blackjack round, saves the result, and
  - if the round resolved - credits any winnings to the user's balance.
  Returns the updated game alongside the (possibly credited) user.
  """
  @spec hit(Scope.t(), BlackjackGame.t()) :: {BlackjackGame.t(), User.t()}
  def hit(%Scope{user: user}, %BlackjackGame{} = game) do
    game |> to_blackjack() |> Blackjack.hit(game.active_hand) |> settle_and_persist(user, game)
  end

  @doc "Stands the active hand of a persisted Blackjack round. See `hit/2`."
  @spec stand(Scope.t(), BlackjackGame.t()) :: {BlackjackGame.t(), User.t()}
  def stand(%Scope{user: user}, %BlackjackGame{} = game) do
    game |> to_blackjack() |> Blackjack.stand(game.active_hand) |> settle_and_persist(user, game)
  end

  defp to_blackjack(%BlackjackGame{} = game) do
    %Blackjack{
      shoe: game.shoe,
      hands: Enum.map(game.hands, &atomize_hand/1),
      active_hand: game.active_hand,
      dealer_hand: game.dealer_hand,
      status: String.to_existing_atom(game.status)
    }
  end

  defp atomize_hand(%{} = hand) do
    %{
      box: hand["box"],
      bet: hand["bet"],
      cards: hand["cards"],
      status: String.to_existing_atom(hand["status"]),
      outcome: hand["outcome"] && String.to_existing_atom(hand["outcome"]),
      payout: hand["payout"]
    }
  end

  defp stringify_hand(%{} = hand) do
    %{
      "box" => hand.box,
      "bet" => hand.bet,
      "cards" => hand.cards,
      "status" => Atom.to_string(hand.status),
      "outcome" => hand.outcome && Atom.to_string(hand.outcome),
      "payout" => hand.payout
    }
  end

  defp persist_blackjack(user, %Blackjack{} = bj) do
    %BlackjackGame{}
    |> BlackjackGame.changeset(%{
      user_id: user.id,
      status: Atom.to_string(bj.status),
      shoe: bj.shoe,
      hands: Enum.map(bj.hands, &stringify_hand/1),
      active_hand: bj.active_hand,
      dealer_hand: bj.dealer_hand,
      round_number: 0
    })
    |> Repo.insert!()
  end

  defp save_blackjack_round(%BlackjackGame{} = game, %Blackjack{} = bj) do
    game
    |> BlackjackGame.changeset(%{
      status: Atom.to_string(bj.status),
      shoe: bj.shoe,
      hands: Enum.map(bj.hands, &stringify_hand/1),
      active_hand: bj.active_hand,
      dealer_hand: bj.dealer_hand,
      round_number: game.round_number + 1
    })
    |> Repo.update!()
  end

  defp settle_and_persist(%Blackjack{} = bj, user, %BlackjackGame{} = game) do
    {:ok, result} =
      Repo.transact(fn ->
        game = save_blackjack_round(game, bj)

        user =
          if bj.status == :round_over do
            total_payout = bj.hands |> Enum.map(& &1.payout) |> Enum.sum()
            {:ok, user} = Accounts.adjust_balance(user, total_payout)
            user
          else
            user
          end

        {:ok, {game, user}}
      end)

    result
  end
end
