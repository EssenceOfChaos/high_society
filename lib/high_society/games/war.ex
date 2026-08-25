defmodule HighSociety.Games.War do
  @moduledoc """
  Pure game logic for War: build/shuffle a deck, deal it, and resolve rounds
  one step at a time, with no dependency on persistence or web.

  A tie triggers a "war": both sides burn three cards face down immediately,
  but the tiebreaker card is *not* flipped automatically. The war is left
  pending (`war` is set on the struct) so the caller can reveal the
  tiebreaker with a separate `play_round/1` call - which may itself tie
  again, chaining into another war.

  Cards are represented as two-character (or three, for "10") strings like
  "AS", "10H", "KD" - rank followed by suit.
  """

  @ranks ~w(2 3 4 5 6 7 8 9 10 J Q K A)
  @suits ~w(S H D C)

  @type card :: String.t()
  @type status :: :in_progress | :player_won | :computer_won
  @type tie :: %{player_card: card, computer_card: card}
  @type war_state :: %{pot: [card], ties: [tie]}
  @type round_result :: %{
          player_card: card | nil,
          computer_card: card | nil,
          winner: :player | :computer | nil,
          war?: boolean,
          pending?: boolean,
          cards_won: non_neg_integer() | nil,
          ties: [tie]
        }

  @type t :: %__MODULE__{
          player_deck: [card],
          computer_deck: [card],
          status: status,
          last_round: round_result | nil,
          war: war_state | nil
        }

  defstruct player_deck: [], computer_deck: [], status: :in_progress, last_round: nil, war: nil

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
  Plays a single step.

  With no war pending, this flips one card each. A mismatch resolves the
  round immediately. A tie burns three cards face down each and leaves the
  war `pending?: true` - nothing is awarded yet.

  With a war already pending, this flips the tiebreaker cards instead,
  awarding the accumulated pot to whichever card is higher (or chaining
  into another war on another tie).
  """
  @spec play_round(t()) :: t()
  def play_round(%__MODULE__{status: :in_progress, war: nil} = game) do
    flip(game, [], [])
  end

  def play_round(%__MODULE__{status: :in_progress, war: %{pot: pot, ties: ties}} = game) do
    flip(%{game | war: nil}, pot, ties)
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

  defp flip(game, pot, ties) do
    [player_card | player_rest] = game.player_deck
    [computer_card | computer_rest] = game.computer_deck
    pot = pot ++ [player_card, computer_card]
    player_value = value(player_card)
    computer_value = value(computer_card)

    cond do
      player_value > computer_value ->
        award(game, :player, player_card, computer_card, player_rest, computer_rest, pot, ties)

      computer_value > player_value ->
        award(game, :computer, player_card, computer_card, player_rest, computer_rest, pot, ties)

      true ->
        declare_war(game, player_card, computer_card, player_rest, computer_rest, pot, ties)
    end
  end

  defp declare_war(game, player_card, computer_card, player_rest, computer_rest, pot, ties) do
    {player_burned, player_rest} = Enum.split(player_rest, 3)
    {computer_burned, computer_rest} = Enum.split(computer_rest, 3)
    pot = pot ++ player_burned ++ computer_burned
    ties = ties ++ [%{player_card: player_card, computer_card: computer_card}]
    game = %{game | player_deck: player_rest, computer_deck: computer_rest}

    cond do
      player_rest == [] -> finish(game, :computer, pot, ties)
      computer_rest == [] -> finish(game, :player, pot, ties)
      true -> pend_war(game, pot, ties)
    end
  end

  defp pend_war(game, pot, ties) do
    last_round = %{
      player_card: nil,
      computer_card: nil,
      winner: nil,
      war?: true,
      pending?: true,
      cards_won: nil,
      ties: ties
    }

    %{game | war: %{pot: pot, ties: ties}, last_round: last_round}
  end

  defp award(
         game,
         winner,
         player_card,
         computer_card,
         player_rest,
         computer_rest,
         pot,
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
      war?: ties != [],
      pending?: false,
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
        status: status,
        war: nil
    }
  end

  defp finish(game, winner, pot, ties) do
    last_round = %{
      player_card: nil,
      computer_card: nil,
      winner: winner,
      war?: true,
      pending?: false,
      cards_won: length(pot),
      ties: ties
    }

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
        last_round: last_round,
        war: nil
    }
  end
end
