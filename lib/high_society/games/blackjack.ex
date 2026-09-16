defmodule HighSociety.Games.Blackjack do
  @moduledoc """
  Pure game logic for Blackjack: deal 1 or 2 player hands ("boxes") against a
  dealer, resolve hits, stands, double downs and splits one step at a time,
  and settle payouts once every hand is finished, with no dependency on
  persistence or web.

  Each dealt box may be split once its two cards share the same value,
  turning it into two hands played one after the other (splitting Aces is
  the exception: each gets exactly one more card and is locked in on the
  spot, and - like any split hand - can't land a bonus-paying blackjack even
  at 21). `hands` therefore grows past its initial 1-or-2 length as splits
  happen, so each hand carries a unique `id` (independent of its
  originating `box`) that stays stable for the rest of the round, letting
  the active hand always be addressed unambiguously.

  Cards are represented as two-character (or three, for "10") strings like
  "AS", "10H", "KD" - rank followed by suit, same encoding as
  `HighSociety.Games.War`.
  """

  @ranks ~w(2 3 4 5 6 7 8 9 10 J Q K A)
  @suits ~w(S H D C)
  # bets are integer cents ($1.00 = 100)
  @max_bet 500 * 100
  @dealer_stands_on 17

  @type card :: String.t()
  @type box :: 0 | 1
  @type hand_id :: non_neg_integer()
  @type hand_status :: :active | :standing | :busted | :blackjack | :surrendered
  @type outcome :: :win | :blackjack_win | :push | :loss | :surrender | nil
  @type hand :: %{
          id: hand_id,
          box: box,
          bet: pos_integer,
          cards: [card],
          status: hand_status,
          outcome: outcome,
          payout: non_neg_integer() | nil,
          split?: boolean(),
          doubled?: boolean()
        }
  @type round_status :: :insurance_offered | :player_turn | :dealer_turn | :round_over
  @type bets :: %{required(box) => pos_integer}
  @type insurance_outcome :: :win | :loss | nil

  @type t :: %__MODULE__{
          shoe: [card],
          hands: [hand],
          active_hand: hand_id | nil,
          dealer_hand: [card],
          status: round_status,
          insurance_bet: non_neg_integer() | nil,
          insurance_outcome: insurance_outcome
        }

  defstruct shoe: [],
            hands: [],
            active_hand: nil,
            dealer_hand: [],
            status: :player_turn,
            insurance_bet: nil,
            insurance_outcome: nil

  @doc "The maximum bet allowed per hand/box."
  @spec max_bet() :: pos_integer()
  def max_bet, do: @max_bet

  @doc """
  Deals a fresh round: shuffles a new shoe, deals two cards to each
  requested box (1 or 2), then two to the dealer. If every dealt hand is
  already a natural blackjack, the round is settled immediately since there
  is no player action to take. Likewise, if the dealer's own two cards are
  already a natural blackjack (any ten-value up-card paired with an Ace
  hole card, or vice versa), the round is settled immediately without
  offering the player any action - mirroring a real dealer peeking at the
  hole card before play begins, so no one can hit, double, or split into a
  bet that's already lost.

  The one exception: if the dealer's up-card is an Ace, the round instead
  pauses in `:insurance_offered` - real money is already on the table and
  whether the dealer is peeked at all now hinges on the player's insurance
  choice, so that decision has to come first. See `take_insurance/1` and
  `decline_insurance/1`.
  """
  @spec new(bets) :: t()
  def new(bets) when map_size(bets) in 1..2 do
    shoe = build_deck() |> Enum.shuffle()
    boxes = bets |> Map.keys() |> Enum.sort()

    {hands, shoe} = deal_hands(boxes, bets, shoe)
    {dealer_hand, shoe} = Enum.split(shoe, 2)

    game = %__MODULE__{shoe: shoe, hands: hands, dealer_hand: dealer_hand}

    if dealer_shows_ace?(dealer_hand) do
      %{game | status: :insurance_offered}
    else
      resolve_after_insurance(game)
    end
  end

  @doc """
  The cost to insure the current round: half the total original wager
  across every dealt box. Only meaningful while `status` is
  `:insurance_offered`.
  """
  @spec insurance_amount(t()) :: pos_integer()
  def insurance_amount(%__MODULE__{hands: hands}) do
    div(Enum.sum(Enum.map(hands, & &1.bet)), 2)
  end

  @doc """
  Takes insurance for half the total original wager (see
  `insurance_amount/1`) and immediately resolves it against the dealer's
  now-peeked hole card: a dealer blackjack settles the round on the spot
  (the insurance more than covers the now-lost main bet - see
  `insurance_payout/1`), while a non-blackjack dealer hand carries on to
  whatever action the player would otherwise face next. Only legal while
  `status` is `:insurance_offered`. Callers are responsible for debiting
  `insurance_amount/1` from the player's balance beforehand.
  """
  @spec take_insurance(t()) :: t()
  def take_insurance(%__MODULE__{status: :insurance_offered} = game) do
    outcome = if blackjack?(game.dealer_hand), do: :win, else: :loss

    %{game | insurance_bet: insurance_amount(game), insurance_outcome: outcome}
    |> resolve_after_insurance()
  end

  @doc """
  Declines insurance, carrying on to whatever action the player would
  otherwise face next. Only legal while `status` is `:insurance_offered`.
  """
  @spec decline_insurance(t()) :: t()
  def decline_insurance(%__MODULE__{status: :insurance_offered} = game) do
    resolve_after_insurance(game)
  end

  @doc """
  The total credited back for insurance: 2-to-1 on top of the insurance
  stake itself (so a winning insurance bet nets exactly enough to offset
  the matching loss on the now-doomed main hand(s)). Zero unless insurance
  was taken and paid off.
  """
  @spec insurance_payout(t()) :: non_neg_integer()
  def insurance_payout(%__MODULE__{insurance_outcome: :win, insurance_bet: bet}), do: bet * 3
  def insurance_payout(%__MODULE__{}), do: 0

  defp dealer_shows_ace?([up_card | _]) do
    {rank, _suit} = split_card(up_card)
    rank == "A"
  end

  defp resolve_after_insurance(%__MODULE__{dealer_hand: dealer_hand} = game) do
    cond do
      blackjack?(dealer_hand) ->
        settle(game)

      hand = Enum.find(game.hands, &(&1.status == :active)) ->
        %{game | active_hand: hand.id, status: :player_turn}

      true ->
        reveal_dealer(game)
    end
  end

  @doc "Draws one card into the active hand. Busts over 21, auto-stands at exactly 21."
  @spec hit(t(), hand_id) :: t()
  def hit(%__MODULE__{status: :player_turn, active_hand: id} = game, id) do
    {card, shoe} = draw(game.shoe)
    hand = get_hand(game, id)
    cards = hand.cards ++ [card]

    game
    |> Map.put(:shoe, shoe)
    |> put_hand(%{hand | cards: cards, status: hit_status(cards)})
    |> advance_turn()
  end

  @doc "Stands the active hand."
  @spec stand(t(), hand_id) :: t()
  def stand(%__MODULE__{status: :player_turn, active_hand: id} = game, id) do
    hand = get_hand(game, id)

    game
    |> put_hand(%{hand | status: :standing})
    |> advance_turn()
  end

  @doc """
  Doubles the active hand's bet, draws exactly one more card, and ends that
  hand's turn regardless of the result (short of a bust, it's forced to
  stand). Only legal as the very first action on a hand - see
  `can_double_down?/2`. Callers are responsible for debiting the matching
  additional bet from the player's balance; this only doubles the `bet`
  field so settlement pays out correctly.
  """
  @spec double_down(t(), hand_id) :: t()
  def double_down(%__MODULE__{status: :player_turn, active_hand: id} = game, id) do
    hand = get_hand(game, id)
    {card, shoe} = draw(game.shoe)
    cards = hand.cards ++ [card]
    status = if busted?(cards), do: :busted, else: :standing

    game
    |> Map.put(:shoe, shoe)
    |> put_hand(%{hand | cards: cards, bet: hand.bet * 2, status: status, doubled?: true})
    |> advance_turn()
  end

  @doc """
  Whether the active hand is eligible to double down: it must still hold
  just its original two cards, i.e. this would be its first action.
  """
  @spec can_double_down?(t(), hand_id) :: boolean()
  def can_double_down?(%__MODULE__{status: :player_turn, active_hand: id} = game, id) do
    hand = get_hand(game, id)
    hand.status == :active and length(hand.cards) == 2
  end

  def can_double_down?(%__MODULE__{}, _id), do: false

  @doc """
  Surrenders the active hand, forfeiting half its bet and ending that
  hand's turn immediately - the other half is returned once the round
  settles (see `settle_hand/2`). Only legal as the very first action on a
  hand - see `can_surrender?/2`. Callers are responsible for crediting the
  returned half once the round settles, same as any other payout.
  """
  @spec surrender(t(), hand_id) :: t()
  def surrender(%__MODULE__{status: :player_turn, active_hand: id} = game, id) do
    hand = get_hand(game, id)

    game
    |> put_hand(%{hand | status: :surrendered})
    |> advance_turn()
  end

  @doc """
  Whether the active hand is eligible to surrender: it must still hold
  just its original two cards (i.e. this would be its first action), and -
  matching standard casino rules - must not itself be the result of a
  split.
  """
  @spec can_surrender?(t(), hand_id) :: boolean()
  def can_surrender?(%__MODULE__{status: :player_turn, active_hand: id} = game, id) do
    hand = get_hand(game, id)
    hand.status == :active and length(hand.cards) == 2 and !hand.split?
  end

  def can_surrender?(%__MODULE__{}, _id), do: false

  @doc """
  Splits the active hand into two hands with matching bets, one per
  original card, each dealt one additional card. Split Aces are the
  exception: each gets exactly that one card and is immediately locked in
  with no further hits - and, like any split hand, neither can land a
  bonus-paying blackjack even if it totals 21. Only legal once, on a still-
  untouched pair of equal-value cards - see `can_split?/2`. As with
  `double_down/2`, the caller must debit the matching additional bet.
  """
  @spec split(t(), hand_id) :: t()
  def split(%__MODULE__{status: :player_turn, active_hand: id} = game, id) do
    hand = get_hand(game, id)
    [card1, card2] = hand.cards
    {new_card1, shoe} = draw(game.shoe)
    {new_card2, shoe} = draw(shoe)
    new_id = length(game.hands)
    locked? = ace_pair?(hand.cards)

    hand_a = build_split_hand(hand, hand.id, [card1, new_card1], locked?)
    hand_b = build_split_hand(hand, new_id, [card2, new_card2], locked?)

    game
    |> Map.put(:shoe, shoe)
    |> replace_with_split(hand.id, hand_a, hand_b)
    |> advance_turn()
  end

  @doc """
  Whether the active hand is eligible to split: an untouched, not-already-
  split pair of same-value cards.
  """
  @spec can_split?(t(), hand_id) :: boolean()
  def can_split?(%__MODULE__{status: :player_turn, active_hand: id} = game, id) do
    hand = get_hand(game, id)

    hand.status == :active and !hand.split? and length(hand.cards) == 2 and
      same_value?(hand.cards)
  end

  def can_split?(%__MODULE__{}, _id), do: false

  @doc "The best total for a hand, treating aces as 11 unless that would bust."
  @spec value([card]) :: non_neg_integer()
  def value(cards) do
    {total, aces} =
      Enum.reduce(cards, {0, 0}, fn card, {total, aces} ->
        {rank, _suit} = split_card(card)
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
  @spec split_card(card) :: {String.t(), String.t()}
  def split_card(card) do
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
        id: box,
        box: box,
        bet: Map.fetch!(bets, box),
        cards: cards,
        status: status,
        outcome: nil,
        payout: nil,
        split?: false,
        doubled?: false
      }

      {hand, shoe}
    end)
  end

  defp hit_status(cards) do
    cond do
      busted?(cards) -> :busted
      value(cards) == 21 -> :standing
      true -> :active
    end
  end

  defp build_split_hand(hand, id, cards, locked?) do
    status = if locked?, do: :standing, else: hit_status(cards)
    %{hand | id: id, cards: cards, status: status, split?: true, doubled?: false}
  end

  defp replace_with_split(%__MODULE__{hands: hands} = game, id, hand_a, hand_b) do
    hands = Enum.flat_map(hands, fn h -> if h.id == id, do: [hand_a, hand_b], else: [h] end)
    %{game | hands: hands}
  end

  defp same_value?([c1, c2]), do: single_card_value(c1) == single_card_value(c2)

  defp ace_pair?([c1, c2]) do
    {r1, _suit} = split_card(c1)
    {r2, _suit} = split_card(c2)
    r1 == "A" and r2 == "A"
  end

  defp single_card_value(card) do
    {rank, _suit} = split_card(card)
    single_rank_value(rank)
  end

  defp single_rank_value("A"), do: 11
  defp single_rank_value(rank) when rank in ~w(J Q K), do: 10
  defp single_rank_value(rank), do: String.to_integer(rank)

  defp draw([card | rest]), do: {card, rest}

  defp get_hand(%__MODULE__{hands: hands}, id), do: Enum.find(hands, &(&1.id == id))

  defp put_hand(%__MODULE__{hands: hands} = game, %{id: id} = updated) do
    %{game | hands: Enum.map(hands, fn hand -> if hand.id == id, do: updated, else: hand end)}
  end

  defp advance_turn(%__MODULE__{hands: hands} = game) do
    case Enum.find(hands, &(&1.status == :active)) do
      %{id: id} -> %{game | active_hand: id, status: :player_turn}
      nil -> reveal_dealer(%{game | active_hand: nil})
    end
  end

  @doc """
  Ends the player phase and flips the dealer's hole card face up, without
  drawing yet. Callers (the LiveView) drive `dealer_step/1` afterwards, one
  call per card, so the dealer's play-out can be paced for the player to
  watch instead of resolving instantly.
  """
  @spec reveal_dealer(t()) :: t()
  def reveal_dealer(%__MODULE__{} = game), do: %{game | active_hand: nil, status: :dealer_turn}

  @doc """
  Advances the dealer by exactly one step: draws a single card if the dealer
  still needs to act, otherwise settles the round. Call this repeatedly
  (checking `status`) after `reveal_dealer/1` until `status` is
  `:round_over`.
  """
  @spec dealer_step(t()) :: t()
  def dealer_step(%__MODULE__{status: :dealer_turn} = game) do
    if needs_dealer_card?(game) do
      {card, shoe} = draw(game.shoe)
      %{game | dealer_hand: game.dealer_hand ++ [card], shoe: shoe}
    else
      settle(game)
    end
  end

  defp needs_dealer_card?(%__MODULE__{hands: hands, dealer_hand: dealer_hand}) do
    Enum.any?(hands, &(&1.status == :standing)) and value(dealer_hand) < @dealer_stands_on
  end

  defp settle(%__MODULE__{} = game) do
    hands = Enum.map(game.hands, &settle_hand(&1, game.dealer_hand))
    %{game | hands: hands, active_hand: nil, status: :round_over}
  end

  defp settle_hand(%{status: :busted} = hand, _dealer_hand),
    do: %{hand | outcome: :loss, payout: 0}

  defp settle_hand(%{status: :surrendered, bet: bet} = hand, _dealer_hand),
    do: %{hand | outcome: :surrender, payout: div(bet, 2)}

  # Reached only when the dealer's own natural blackjack settles the round
  # before the player got to act (see `new/1`) - a still-untouched hand is
  # by definition not itself a natural (those are dealt straight to
  # `:blackjack`), so it always loses. Moved to `:standing` since it's now
  # resolved, same as every other settled hand.
  defp settle_hand(%{status: :active} = hand, _dealer_hand),
    do: %{hand | status: :standing, outcome: :loss, payout: 0}

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
