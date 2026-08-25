defmodule HighSociety.Games.War do
  @moduledoc """
  Pure game logic for War: build/shuffle a deck, deal it, and resolve rounds
  (including chained "war" ties) with no dependency on persistence or web.

  Cards are represented as two-character (or three, for "10") strings like
  "AS", "10H", "KD" - rank followed by suit.
  """

  @ranks ~w(2 3 4 5 6 7 8 9 10 J Q K A)
  @suits ~w(S H D C)

  @type card :: String.t()
  @type status :: :in_progress | :player_won | :computer_won
  @type tie :: %{player_card: card, computer_card: card}
  @type round_result :: %{
          player_card: card,
          computer_card: card,
          winner: :player | :computer,
          war?: boolean,
          cards_won: non_neg_integer(),
          ties: [tie]
        }

  @type t :: %__MODULE__{
          player_deck: [card],
          computer_deck: [card],
          status: status,
          last_round: round_result | nil
        }

  defstruct player_deck: [], computer_deck: [], status: :in_progress, last_round: nil

  @doc "Builds a fresh, shuffled deck and deals it evenly between player and computer."
  @spec new() :: t()
  def new do
    {player_deck, computer_deck} =
      build_deck()
      |> Enum.shuffle()
      |> Enum.split(26)

    %__MODULE__{player_deck: player_deck, computer_deck: computer_deck, status: :in_progress}
  end

  @doc """
  Plays a single round (flipping one card each). Ties trigger a "war": each
  side burns cards face down and flips again until the tie is broken or a
  player runs out of cards. Returns the updated game with `last_round` set to
  a summary of what happened, and `status` updated when the game has ended.
  """
  @spec play_round(t()) :: t()
  def play_round(%__MODULE__{status: :in_progress} = game) do
    resolve(game, [], false, [])
  end

  @spec build_deck() :: [card]
  defp build_deck do
    for rank <- @ranks, suit <- @suits, do: rank <> suit
  end

  @spec value(card) :: non_neg_integer()
  def value(card) do
    {rank, _suit} = split(card)
    Enum.find_index(@ranks, &(&1 == rank)) + 2
  end

  @doc "Splits a card string into its `{rank, suit}` parts."
  @spec split(card) :: {String.t(), String.t()}
  def split(card) do
    suit = String.last(card)
    rank = String.slice(card, 0, String.length(card) - 1)
    {rank, suit}
  end

  defp resolve(game, pot, war?, ties, reveal \\ nil) do
    case {game.player_deck, game.computer_deck} do
      {[], _} ->
        finish(game, :computer, pot, war?, ties, reveal)

      {_, []} ->
        finish(game, :player, pot, war?, ties, reveal)

      {[player_card | player_rest], [computer_card | computer_rest]} ->
        pot = pot ++ [player_card, computer_card]
        player_value = value(player_card)
        computer_value = value(computer_card)

        cond do
          player_value > computer_value ->
            award(
              game,
              :player,
              player_card,
              computer_card,
              player_rest,
              computer_rest,
              pot,
              war?,
              ties
            )

          computer_value > player_value ->
            award(
              game,
              :computer,
              player_card,
              computer_card,
              player_rest,
              computer_rest,
              pot,
              war?,
              ties
            )

          true ->
            {player_burned, player_rest} = Enum.split(player_rest, 3)
            {computer_burned, computer_rest} = Enum.split(computer_rest, 3)
            pot = pot ++ player_burned ++ computer_burned
            ties = ties ++ [%{player_card: player_card, computer_card: computer_card}]

            game
            |> Map.put(:player_deck, player_rest)
            |> Map.put(:computer_deck, computer_rest)
            |> resolve(pot, true, ties, {player_card, computer_card})
        end
    end
  end

  defp award(
         game,
         winner,
         player_card,
         computer_card,
         player_rest,
         computer_rest,
         pot,
         war?,
         ties
       ) do
    won_pot = Enum.shuffle(pot)

    {player_deck, computer_deck} =
      case winner do
        :player -> {player_rest ++ won_pot, computer_rest}
        :computer -> {player_rest, computer_rest ++ won_pot}
      end

    last_round = %{
      player_card: player_card,
      computer_card: computer_card,
      winner: winner,
      war?: war?,
      cards_won: length(pot),
      ties: ties
    }

    status =
      cond do
        player_deck == [] -> :computer_won
        computer_deck == [] -> :player_won
        true -> :in_progress
      end

    %{
      game
      | player_deck: player_deck,
        computer_deck: computer_deck,
        last_round: last_round,
        status: status
    }
  end

  defp finish(game, winner, pot, war?, ties, reveal) do
    last_round =
      case reveal do
        nil ->
          game.last_round

        {player_card, computer_card} ->
          %{
            player_card: player_card,
            computer_card: computer_card,
            winner: winner,
            war?: war?,
            cards_won: length(pot),
            ties: ties
          }
      end

    status = if winner == :player, do: :player_won, else: :computer_won
    won_pot = Enum.shuffle(pot)

    {player_deck, computer_deck} =
      case winner do
        :player -> {game.player_deck ++ won_pot, game.computer_deck}
        :computer -> {game.player_deck, game.computer_deck ++ won_pot}
      end

    %{
      game
      | player_deck: player_deck,
        computer_deck: computer_deck,
        status: status,
        last_round: last_round
    }
  end
end
