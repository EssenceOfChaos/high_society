defmodule HighSociety.Games do
  @moduledoc """
  The Games context. Owns persistence for the individual card games (starting
  with War) and translates between their pure game-logic structs and the
  Ecto schemas used to store game state in Postgres.
  """

  import Ecto.Query, warn: false

  alias HighSociety.Accounts.Scope
  alias HighSociety.Repo
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
end
