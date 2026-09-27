defmodule HighSociety.Games.Baccarat do
  @moduledoc """
  Pure game logic for Punto Banco Baccarat: build/shuffle a deck, deal
  Player and Banker hands per the standard fixed drawing rules (no player
  decisions - a round resolves in one step), and settle Player/Banker/Tie
  bets against the result. No dependency on persistence or web.

  Cards are represented the same way as `HighSociety.Games.War` and
  `HighSociety.Games.Blackjack` - two-character (or three, for "10")
  strings like "AS", "10H", "KD" - rank followed by suit.

  A bet is keyed by which side it covers - `"player"`, `"banker"`, or
  `"tie"` - mapped to its wagered amount, mirroring
  `HighSociety.Games.Roulette`'s bet-map convention.
  """

  @ranks ~w(2 3 4 5 6 7 8 9 10 J Q K A)
  @suits ~w(S H D C)

  @max_bet 500 * 100

  @type card :: String.t()
  @type bet_key :: String.t()
  @type bets :: %{bet_key() => pos_integer()}
  @type outcome :: :player | :banker | :tie
  @type settled_bet :: %{
          key: bet_key(),
          amount: pos_integer(),
          payout: non_neg_integer(),
          won?: boolean()
        }

  @type t :: %__MODULE__{
          player_hand: [card],
          banker_hand: [card],
          player_total: 0..9,
          banker_total: 0..9,
          outcome: outcome,
          bets: [settled_bet]
        }

  defstruct player_hand: [],
            banker_hand: [],
            player_total: 0,
            banker_total: 0,
            outcome: nil,
            bets: []

  @doc "The maximum amount that may be wagered on any single spot."
  @spec max_bet() :: pos_integer()
  def max_bet, do: @max_bet

  @doc "Whether `key` is a bet this module knows how to settle - Player, Banker, or Tie."
  @spec valid_key?(bet_key()) :: boolean()
  def valid_key?(key), do: key in ~w(player banker tie)

  @doc """
  Deals a full round: builds a fresh shuffled shoe, deals Player and
  Banker their two cards each, draws third cards per the standard
  drawing tableau below, determines the winning side, and settles every
  entry in `bets` against it.

  Drawing rules (no player decisions - purely mechanical):
    - A two-card total of 8 or 9 for either side ("natural") ends the
      hand immediately - neither side draws a third card.
    - Otherwise Player draws a third card on a total of 0-5, stands on
      6-7.
    - Banker's third card then depends on Banker's own two-card total
      and (if Player drew) the value of Player's third card - the fixed
      table implemented in `banker_draws_after_player_third?/2` - or, if
      Player stood, Banker uses the same 0-5/6-7 rule Player used.

  Payouts (the stake is always included in a winning `payout`, same
  convention as `Roulette.evaluate/2`): Player 1:1, Banker 0.95:1 (5%
  commission, via integer division - Tokens have no fractional amounts),
  Tie 8:1. On a Tie result, Player/Banker bets push (payout equals the
  original amount, `won?: false` since nothing was profited) rather than
  losing - only Tie bets win or lose outright on a tie.
  """
  @spec deal(bets()) :: t()
  def deal(bets) when is_map(bets) do
    deck = build_deck() |> Enum.shuffle()

    {p1, deck} = pop(deck)
    {b1, deck} = pop(deck)
    {p2, deck} = pop(deck)
    {b2, deck} = pop(deck)

    resolve([p1, p2], [b1, b2], deck, bets)
  end

  @doc """
  Resolves a round given the two starting hands and the remaining shoe to
  draw third cards from - the same logic `deal/1` uses, split out so the
  drawing tableau and settlement math can be exercised with fixed hands
  instead of a real shuffle (mirroring how
  `HighSociety.Games.Blackjack`'s tests build a struct directly with a
  hand-picked shoe for the same reason).
  """
  @spec resolve([card], [card], [card], bets()) :: t()
  def resolve(player_hand, banker_hand, deck, bets) do
    {player_hand, banker_hand} =
      if hand_total(player_hand) >= 8 or hand_total(banker_hand) >= 8 do
        {player_hand, banker_hand}
      else
        {player_hand, banker_hand, _deck} = draw_third_cards(player_hand, banker_hand, deck)
        {player_hand, banker_hand}
      end

    player_total = hand_total(player_hand)
    banker_total = hand_total(banker_hand)

    outcome =
      cond do
        player_total > banker_total -> :player
        banker_total > player_total -> :banker
        true -> :tie
      end

    %__MODULE__{
      player_hand: player_hand,
      banker_hand: banker_hand,
      player_total: player_total,
      banker_total: banker_total,
      outcome: outcome,
      bets: Enum.map(bets, &settle_bet(&1, outcome))
    }
  end

  @doc "A card's Baccarat point value: Ace = 1, 2-9 = face value, 10/J/Q/K = 0."
  @spec point_value(card) :: 0..9
  def point_value(card) do
    case split_card(card) do
      {"A", _suit} -> 1
      {rank, _suit} when rank in ~w(10 J Q K) -> 0
      {rank, _suit} -> String.to_integer(rank)
    end
  end

  @doc "A hand's total: the sum of its cards' point values, mod 10."
  @spec hand_total([card]) :: 0..9
  def hand_total(hand), do: hand |> Enum.map(&point_value/1) |> Enum.sum() |> rem(10)

  @doc "Splits a card string into its `{rank, suit}` parts."
  @spec split_card(card) :: {String.t(), String.t()}
  def split_card(card) do
    suit = String.last(card)
    rank = String.slice(card, 0, String.length(card) - 1)
    {rank, suit}
  end

  @spec build_deck() :: [card]
  defp build_deck, do: for(rank <- @ranks, suit <- @suits, do: rank <> suit)

  defp pop([card | rest]), do: {card, rest}

  defp draw_third_cards(player_hand, banker_hand, deck) do
    player_total = hand_total(player_hand)

    if player_total in 0..5 do
      {player_third, deck} = pop(deck)
      player_hand = player_hand ++ [player_third]

      if banker_draws_after_player_third?(hand_total(banker_hand), point_value(player_third)) do
        {banker_third, deck} = pop(deck)
        {player_hand, banker_hand ++ [banker_third], deck}
      else
        {player_hand, banker_hand, deck}
      end
    else
      if hand_total(banker_hand) in 0..5 do
        {banker_third, deck} = pop(deck)
        {player_hand, banker_hand ++ [banker_third], deck}
      else
        {player_hand, banker_hand, deck}
      end
    end
  end

  @doc """
  The standard fixed table for whether Banker draws a third card, keyed
  by Banker's own two-card total and the value of Player's third card -
  exposed publicly (like `HighSociety.Games.Blackjack.can_split?/2` and
  friends) so this well-known rule can be tested directly against its
  official values instead of only indirectly through `deal/1`/`resolve/4`.
  """
  @spec banker_draws_after_player_third?(0..7, 0..9) :: boolean()
  def banker_draws_after_player_third?(banker_total, _player_third_value)
      when banker_total in 0..2,
      do: true

  def banker_draws_after_player_third?(3, player_third_value), do: player_third_value != 8
  def banker_draws_after_player_third?(4, player_third_value), do: player_third_value in 2..7
  def banker_draws_after_player_third?(5, player_third_value), do: player_third_value in 4..7
  def banker_draws_after_player_third?(6, player_third_value), do: player_third_value in 6..7
  def banker_draws_after_player_third?(7, _player_third_value), do: false

  defp settle_bet({"player", amount}, :player),
    do: %{key: "player", amount: amount, payout: amount * 2, won?: true}

  defp settle_bet({"player", amount}, :tie),
    do: %{key: "player", amount: amount, payout: amount, won?: false}

  defp settle_bet({"player", amount}, :banker),
    do: %{key: "player", amount: amount, payout: 0, won?: false}

  defp settle_bet({"banker", amount}, :banker),
    do: %{key: "banker", amount: amount, payout: amount + div(amount * 19, 20), won?: true}

  defp settle_bet({"banker", amount}, :tie),
    do: %{key: "banker", amount: amount, payout: amount, won?: false}

  defp settle_bet({"banker", amount}, :player),
    do: %{key: "banker", amount: amount, payout: 0, won?: false}

  defp settle_bet({"tie", amount}, :tie),
    do: %{key: "tie", amount: amount, payout: amount * 9, won?: true}

  defp settle_bet({"tie", amount}, _outcome),
    do: %{key: "tie", amount: amount, payout: 0, won?: false}
end
