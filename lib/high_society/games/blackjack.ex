defmodule HighSociety.Games.Blackjack do
  @moduledoc """
  Pure game logic for Blackjack: deal 1 or 2 player hands ("boxes") against a
  dealer, resolve hits and stands one step at a time, and settle payouts once
  every hand is finished, with no dependency on persistence or web.

  Hit/Stand only for now - no double down or split - but `hands` is a list
  (not a fixed pair) and each hand's `cards` list has no length assumption,
  so both can be added later without reshaping this struct.

  Cards are represented as two-character (or three, for "10") strings like
  "AS", "10H", "KD" - rank followed by suit, same encoding as
  `HighSociety.Games.War`.
  """

  @ranks ~w(2 3 4 5 6 7 8 9 10 J Q K A)
  @suits ~w(S H D C)
  @max_bet 500
  @dealer_stands_on 17

  @type card :: String.t()
  @type box :: 0 | 1
  @type hand_status :: :active | :standing | :busted | :blackjack
  @type outcome :: :win | :blackjack_win | :push | :loss | nil
  @type hand :: %{
          box: box,
          bet: pos_integer,
          cards: [card],
          status: hand_status,
          outcome: outcome,
          payout: non_neg_integer() | nil
        }
  @type round_status :: :player_turn | :dealer_turn | :round_over
  @type bets :: %{required(box) => pos_integer}

  @type t :: %__MODULE__{
          shoe: [card],
          hands: [hand],
          active_hand: box | nil,
          dealer_hand: [card],
          status: round_status
        }

  defstruct shoe: [], hands: [], active_hand: nil, dealer_hand: [], status: :player_turn

  @doc "The maximum bet allowed per hand/box."
  @spec max_bet() :: pos_integer()
  def max_bet, do: @max_bet

  @doc """
  Deals a fresh round: shuffles a new shoe, deals two cards to each
  requested box (1 or 2), then two to the dealer. If every dealt hand is
  already a natural blackjack, the round is settled immediately since there
  is no player action to take.
  """
  @spec new(bets) :: t()
  def new(bets) when map_size(bets) in 1..2 do
    shoe = build_deck() |> Enum.shuffle()
    boxes = bets |> Map.keys() |> Enum.sort()

    {hands, shoe} = deal_hands(boxes, bets, shoe)
    {dealer_hand, shoe} = Enum.split(shoe, 2)

    game = %__MODULE__{shoe: shoe, hands: hands, dealer_hand: dealer_hand}

    case Enum.find(hands, &(&1.status == :active)) do
      %{box: box} -> %{game | active_hand: box, status: :player_turn}
      nil -> play_dealer_and_settle(game)
    end
  end

  @doc "Draws one card into the active hand. Busts over 21, auto-stands at exactly 21."
  @spec hit(t(), box) :: t()
  def hit(%__MODULE__{status: :player_turn, active_hand: box} = game, box) do
    {card, shoe} = draw(game.shoe)
    hand = get_hand(game, box)
    cards = hand.cards ++ [card]

    status =
      cond do
        busted?(cards) -> :busted
        value(cards) == 21 -> :standing
        true -> :active
      end

    game
    |> Map.put(:shoe, shoe)
    |> put_hand(%{hand | cards: cards, status: status})
    |> advance_turn()
  end

  @doc "Stands the active hand."
  @spec stand(t(), box) :: t()
  def stand(%__MODULE__{status: :player_turn, active_hand: box} = game, box) do
    hand = get_hand(game, box)

    game
    |> put_hand(%{hand | status: :standing})
    |> advance_turn()
  end

  @doc "The best total for a hand, treating aces as 11 unless that would bust."
  @spec value([card]) :: non_neg_integer()
  def value(cards) do
    {total, aces} =
      Enum.reduce(cards, {0, 0}, fn card, {total, aces} ->
        {rank, _suit} = split(card)
        rank_value(rank, total, aces)
      end)

    reduce_for_aces(total, aces)
  end

  defp rank_value("A", total, aces), do: {total + 11, aces + 1}
  defp rank_value(rank, total, aces) when rank in ~w(J Q K), do: {total + 10, aces}
  defp rank_value(rank, total, aces), do: {total + String.to_integer(rank), aces}

  defp reduce_for_aces(total, aces) when total > 21 and aces > 0,
    do: reduce_for_aces(total - 10, aces - 1)

  defp reduce_for_aces(total, _aces), do: total

  @doc "Whether the given two-card hand is a natural blackjack."
  @spec blackjack?([card]) :: boolean()
  def blackjack?(cards), do: length(cards) == 2 and value(cards) == 21

  @doc "Whether the given hand has busted (total over 21)."
  @spec busted?([card]) :: boolean()
  def busted?(cards), do: value(cards) > 21

  @doc "Splits a card string into its `{rank, suit}` parts."
  @spec split(card) :: {String.t(), String.t()}
  def split(card) do
    suit = String.last(card)
    rank = String.slice(card, 0, String.length(card) - 1)
    {rank, suit}
  end

  @spec build_deck() :: [card]
  defp build_deck do
    for rank <- @ranks, suit <- @suits, do: rank <> suit
  end

  defp deal_hands(boxes, bets, shoe) do
    Enum.map_reduce(boxes, shoe, fn box, shoe ->
      {cards, shoe} = Enum.split(shoe, 2)
      status = if blackjack?(cards), do: :blackjack, else: :active

      hand = %{
        box: box,
        bet: Map.fetch!(bets, box),
        cards: cards,
        status: status,
        outcome: nil,
        payout: nil
      }

      {hand, shoe}
    end)
  end

  defp draw([card | rest]), do: {card, rest}

  defp get_hand(%__MODULE__{hands: hands}, box), do: Enum.find(hands, &(&1.box == box))

  defp put_hand(%__MODULE__{hands: hands} = game, %{box: box} = updated) do
    %{game | hands: Enum.map(hands, fn hand -> if hand.box == box, do: updated, else: hand end)}
  end

  defp advance_turn(%__MODULE__{hands: hands} = game) do
    case Enum.find(hands, &(&1.status == :active)) do
      %{box: box} -> %{game | active_hand: box, status: :player_turn}
      nil -> play_dealer_and_settle(%{game | active_hand: nil})
    end
  end

  defp play_dealer_and_settle(%__MODULE__{} = game) do
    game = play_dealer(game)
    hands = Enum.map(game.hands, &settle_hand(&1, game.dealer_hand))
    %{game | hands: hands, active_hand: nil, status: :round_over}
  end

  defp play_dealer(%__MODULE__{dealer_hand: dealer_hand, shoe: shoe} = game) do
    if value(dealer_hand) < @dealer_stands_on do
      {card, shoe} = draw(shoe)
      play_dealer(%{game | dealer_hand: dealer_hand ++ [card], shoe: shoe})
    else
      game
    end
  end

  defp settle_hand(%{status: :busted} = hand, _dealer_hand),
    do: %{hand | outcome: :loss, payout: 0}

  defp settle_hand(%{status: :blackjack, bet: bet} = hand, dealer_hand) do
    if blackjack?(dealer_hand) do
      %{hand | outcome: :push, payout: bet}
    else
      %{hand | outcome: :blackjack_win, payout: bet + div(bet * 3, 2)}
    end
  end

  defp settle_hand(%{status: :standing, bet: bet, cards: cards} = hand, dealer_hand) do
    cond do
      blackjack?(dealer_hand) -> %{hand | outcome: :loss, payout: 0}
      busted?(dealer_hand) -> %{hand | outcome: :win, payout: bet * 2}
      value(cards) > value(dealer_hand) -> %{hand | outcome: :win, payout: bet * 2}
      value(cards) == value(dealer_hand) -> %{hand | outcome: :push, payout: bet}
      true -> %{hand | outcome: :loss, payout: 0}
    end
  end
end
