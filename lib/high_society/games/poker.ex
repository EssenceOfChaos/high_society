defmodule HighSociety.Games.Poker do
  @moduledoc """
  Pure game logic for a single No-Limit Texas Hold'em hand: deals hole
  cards, posts blinds, resolves check/fold/call/bet/raise one action at a
  time, deals each subsequent street, and settles the pot(s) - including
  side pots for multiple all-ins - at showdown, with no dependency on
  persistence, timers, or web.

  This struct only ever represents *one hand in progress*. The durable,
  between-hands state (who's seated where, with how many chips) is owned
  by `HighSociety.Games.PokerTable`; that GenServer calls `start_hand/4`
  with a fresh snapshot of occupied seats and stacks each time a hand
  begins, and reads the final per-seat `stack` back out of this struct once
  `status` reaches `:hand_over` to update its own durable seat map.

  Cards are represented as two-character (or three, for "10") strings like
  "AS", "10H", "KD" - rank followed by suit, same encoding as
  `HighSociety.Games.Blackjack`.

  Every action function returns `{:ok, t()} | {:error, reason}` rather than
  matching only on legal preconditions (unlike `Blackjack`): a table is
  driven by several independently-connected players, so a stale or
  mistimed client request (a double-click, a request that raced a timeout)
  must be safely rejected instead of crashing the table's process.

  One simplification worth calling out: a short all-in raise (for less than
  a full raise increment) still reopens the action for every other live
  seat here, rather than only letting them call-and-not-reraise as strict
  casino rules would. That edge case is rare and never affects chip
  totals - only how much action a tiny short all-in can re-open - so it's
  left simple rather than tracking a second "can't reraise" seat flag.
  """

  alias HighSociety.Games.Poker.HandEvaluator

  @ranks ~w(2 3 4 5 6 7 8 9 10 J Q K A)
  @suits ~w(S H D C)

  @type card :: String.t()
  @type seat_index :: 0..7
  @type seat_status :: :active | :folded | :all_in
  @type street :: :preflop | :flop | :turn | :river
  @type hand_status :: :in_progress | :hand_over

  @type seat :: %{
          user_id: pos_integer(),
          username: String.t(),
          hole_cards: [card],
          stack: non_neg_integer(),
          status: seat_status,
          contributed_this_street: non_neg_integer(),
          total_contributed: non_neg_integer(),
          acted?: boolean()
        }

  @type pot :: %{
          amount: non_neg_integer(),
          eligible: [seat_index],
          winners: [seat_index] | nil,
          award_each: non_neg_integer() | nil,
          extra_chip_winners: [seat_index] | nil
        }

  @type t :: %__MODULE__{
          seats: %{seat_index => seat},
          button_seat: seat_index,
          deck: [card],
          community_cards: [card],
          street: street,
          status: hand_status,
          small_blind: pos_integer(),
          big_blind: pos_integer(),
          current_bet: non_neg_integer(),
          min_raise: pos_integer(),
          action_on: seat_index | nil,
          pots: [pot] | nil,
          uncalled_return: %{seat: seat_index, amount: pos_integer()} | nil
        }

  defstruct seats: %{},
            button_seat: nil,
            deck: [],
            community_cards: [],
            street: :preflop,
            status: :in_progress,
            small_blind: 0,
            big_blind: 0,
            current_bet: 0,
            min_raise: 0,
            action_on: nil,
            pots: nil,
            uncalled_return: nil

  @doc """
  Deals a fresh hand to every occupied seat in `seats` (a map of seat index
  to `%{user_id, username, stack}`, at least 2 entries), posts blinds
  (rotating from `button_seat`, which must itself be one of the occupied
  seats), and sets the action to whoever acts first. Heads-up (exactly 2
  seats) is a special case: the button posts the small blind and acts
  first preflop; with 3+ seats, blinds pass clockwise from the button and
  the seat left of the big blind acts first.
  """
  @spec start_hand(%{seat_index => map()}, seat_index, pos_integer(), pos_integer()) :: t()
  def start_hand(seats, button_seat, small_blind, big_blind) when map_size(seats) >= 2 do
    occupied = seats |> Map.keys() |> Enum.sort()
    deck = build_deck() |> Enum.shuffle()

    {seat_entries, deck} =
      Enum.map_reduce(occupied, deck, fn seat_index, deck ->
        {hole_cards, deck} = Enum.split(deck, 2)
        %{user_id: user_id, username: username, stack: stack} = Map.fetch!(seats, seat_index)

        entry = %{
          user_id: user_id,
          username: username,
          hole_cards: hole_cards,
          stack: stack,
          status: :active,
          contributed_this_street: 0,
          total_contributed: 0,
          acted?: false
        }

        {{seat_index, entry}, deck}
      end)

    {sb_seat, bb_seat} = blind_seats(occupied, button_seat)

    poker = %__MODULE__{
      seats: Map.new(seat_entries),
      button_seat: button_seat,
      deck: deck,
      small_blind: small_blind,
      big_blind: big_blind,
      min_raise: big_blind
    }

    poker =
      poker
      |> post_blind(sb_seat, small_blind)
      |> post_blind(bb_seat, big_blind)

    first_to_act_candidate =
      if length(occupied) == 2, do: sb_seat, else: next_seat_clockwise(occupied, bb_seat)

    poker
    |> Map.put(:action_on, first_to_act_candidate)
    |> resolve_start(occupied)
  end

  @doc "Checks: only legal when nothing is outstanding to call."
  @spec check(t(), seat_index) :: {:ok, t()} | {:error, atom()}
  def check(%__MODULE__{} = poker, seat) do
    cond do
      not action_on?(poker, seat) ->
        {:error, :not_your_turn}

      Map.fetch!(poker.seats, seat).contributed_this_street != poker.current_bet ->
        {:error, :bet_outstanding}

      true ->
        {:ok, poker |> mark_acted(seat) |> advance_action()}
    end
  end

  @doc "Folds: always legal on the acting seat's own turn."
  @spec fold(t(), seat_index) :: {:ok, t()} | {:error, atom()}
  def fold(%__MODULE__{} = poker, seat) do
    if action_on?(poker, seat) do
      poker = update_seat(poker, seat, &%{&1 | status: :folded})
      {:ok, advance_action(poker)}
    else
      {:error, :not_your_turn}
    end
  end

  @doc """
  Calls the outstanding bet - or, if the seat's stack is short, calls
  all-in for whatever remains.
  """
  @spec call(t(), seat_index) :: {:ok, t()} | {:error, atom()}
  def call(%__MODULE__{} = poker, seat) do
    cond do
      not action_on?(poker, seat) ->
        {:error, :not_your_turn}

      poker.current_bet == 0 ->
        {:error, :nothing_to_call}

      true ->
        seat_data = Map.fetch!(poker.seats, seat)
        to_amount = min(poker.current_bet, seat_data.stack + seat_data.contributed_this_street)
        poker = poker |> apply_wager(seat, to_amount) |> mark_acted(seat)
        {:ok, advance_action(poker)}
    end
  end

  @doc """
  Opens betting for `to_amount` total this street. Only legal when no bet
  is outstanding yet; `to_amount` must be at least the big blind (or the
  seat's entire stack, if that's less) and at most the seat's stack.
  """
  @spec bet(t(), seat_index, pos_integer()) :: {:ok, t()} | {:error, atom()}
  def bet(%__MODULE__{} = poker, seat, to_amount) do
    cond do
      not action_on?(poker, seat) ->
        {:error, :not_your_turn}

      poker.current_bet > 0 ->
        {:error, :bet_already_outstanding}

      true ->
        seat_data = Map.fetch!(poker.seats, seat)
        max_amount = seat_data.stack + seat_data.contributed_this_street
        min_amount = min(poker.big_blind, max_amount)

        cond do
          to_amount > max_amount ->
            {:error, :exceeds_stack}

          to_amount < min_amount ->
            {:error, :below_minimum}

          true ->
            {:ok,
             poker |> apply_wager(seat, to_amount) |> mark_aggressor(seat) |> advance_action()}
        end
    end
  end

  @doc """
  Raises the outstanding bet to `to_amount` total this street (not the
  increment - the new total, matching how a table would call it out).
  Must be at least the previous bet plus the last raise's size, unless
  it's an all-in for less.
  """
  @spec raise(t(), seat_index, pos_integer()) :: {:ok, t()} | {:error, atom()}
  def raise(%__MODULE__{} = poker, seat, to_amount) do
    cond do
      not action_on?(poker, seat) ->
        {:error, :not_your_turn}

      poker.current_bet == 0 ->
        {:error, :no_bet_to_raise}

      true ->
        seat_data = Map.fetch!(poker.seats, seat)
        max_amount = seat_data.stack + seat_data.contributed_this_street
        min_to = min(poker.current_bet + poker.min_raise, max_amount)

        cond do
          to_amount > max_amount ->
            {:error, :exceeds_stack}

          to_amount <= poker.current_bet ->
            {:error, :must_exceed_current_bet}

          to_amount < min_to ->
            {:error, :below_minimum_raise}

          true ->
            {:ok,
             poker |> apply_wager(seat, to_amount) |> mark_aggressor(seat) |> advance_action()}
        end
    end
  end

  @doc """
  Forfeits the seat currently on the clock: checks if that's legal,
  otherwise folds. A stale call (the seat isn't actually on the action
  anymore) is a safe no-op, returning the hand unchanged.
  """
  @spec timeout(t(), seat_index) :: t()
  def timeout(%__MODULE__{} = poker, seat) do
    cond do
      not action_on?(poker, seat) ->
        poker

      Map.fetch!(poker.seats, seat).contributed_this_street == poker.current_bet ->
        {:ok, poker} = check(poker, seat)
        poker

      true ->
        {:ok, poker} = fold(poker, seat)
        poker
    end
  end

  @doc """
  Folds a seat regardless of whose turn it actually is - for a player
  standing up mid-hand, who isn't necessarily the one currently on the
  clock. Only advances the action itself if it genuinely was that seat's
  turn; otherwise leaves `action_on` untouched (someone else is still
  deciding) but still checks whether removing this seat leaves only one
  hand standing, settling immediately if so.
  """
  @spec force_fold(t(), seat_index) :: t()
  def force_fold(%__MODULE__{status: :hand_over} = poker, _seat), do: poker

  def force_fold(%__MODULE__{status: :in_progress, action_on: seat} = poker, seat) do
    poker |> update_seat(seat, &%{&1 | status: :folded}) |> advance_action()
  end

  def force_fold(%__MODULE__{status: :in_progress} = poker, seat) do
    poker = update_seat(poker, seat, &%{&1 | status: :folded})
    if live_count(poker) <= 1, do: settle_uncontested(poker), else: poker
  end

  defp action_on?(%__MODULE__{status: :in_progress, action_on: seat}, seat), do: true
  defp action_on?(%__MODULE__{}, _seat), do: false

  defp blind_seats(occupied, button_seat) when length(occupied) == 2 do
    [other_seat] = occupied -- [button_seat]
    {button_seat, other_seat}
  end

  defp blind_seats(occupied, button_seat) do
    small_blind_seat = next_seat_clockwise(occupied, button_seat)
    big_blind_seat = next_seat_clockwise(occupied, small_blind_seat)
    {small_blind_seat, big_blind_seat}
  end

  defp post_blind(poker, seat, amount) do
    seat_data = Map.fetch!(poker.seats, seat)
    post_amount = min(amount, seat_data.stack)

    poker
    |> update_seat(seat, fn s ->
      remaining = s.stack - post_amount

      %{
        s
        | stack: remaining,
          contributed_this_street: post_amount,
          total_contributed: post_amount,
          status: if(remaining == 0, do: :all_in, else: :active)
      }
    end)
    |> then(&%{&1 | current_bet: max(&1.current_bet, post_amount)})
  end

  # Resolves the seat that should actually open the action once blinds are
  # posted: skips over the naive candidate if it's already all-in on its
  # blind, and runs the whole hand out street-by-street (no action possible)
  # if every seat is already all-in or folded.
  defp resolve_start(poker, occupied) do
    if count_active(poker) == 0 do
      %{poker | action_on: nil} |> advance_street_or_showdown()
    else
      %{poker | action_on: find_active_from(poker, poker.action_on, occupied)}
    end
  end

  defp mark_acted(poker, seat), do: update_seat(poker, seat, &%{&1 | acted?: true})

  # A bet or raise reopens the action for every other still-active seat
  # (see the moduledoc note on short all-in raises) and records the new
  # amount to call plus the size of this raise, for sizing the next one.
  defp mark_aggressor(poker, seat) do
    seat_data = Map.fetch!(poker.seats, seat)
    increment = seat_data.contributed_this_street - poker.current_bet

    poker = %{
      poker
      | current_bet: seat_data.contributed_this_street,
        min_raise: max(poker.big_blind, increment)
    }

    seats =
      Map.new(poker.seats, fn
        {^seat, s} -> {seat, %{s | acted?: true}}
        {i, %{status: :active} = s} -> {i, %{s | acted?: false}}
        {i, s} -> {i, s}
      end)

    %{poker | seats: seats}
  end

  defp apply_wager(poker, seat, to_amount) do
    update_seat(poker, seat, fn s ->
      delta = to_amount - s.contributed_this_street
      remaining = s.stack - delta

      %{
        s
        | stack: remaining,
          contributed_this_street: to_amount,
          total_contributed: s.total_contributed + delta,
          status: if(remaining == 0, do: :all_in, else: s.status)
      }
    end)
  end

  defp update_seat(poker, seat, fun), do: %{poker | seats: Map.update!(poker.seats, seat, fun)}

  defp advance_action(poker) do
    cond do
      live_count(poker) <= 1 -> settle_uncontested(poker)
      all_settled?(poker) -> advance_street_or_showdown(poker)
      true -> move_to_next_actor(poker)
    end
  end

  defp move_to_next_actor(poker) do
    occupied = occupied_seats(poker)
    start = next_seat_clockwise(occupied, poker.action_on)
    %{poker | action_on: find_active_from(poker, start, occupied)}
  end

  defp advance_street_or_showdown(%{street: :preflop} = poker),
    do: deal_next_street(poker, :flop, 3)

  defp advance_street_or_showdown(%{street: :flop} = poker), do: deal_next_street(poker, :turn, 1)

  defp advance_street_or_showdown(%{street: :turn} = poker),
    do: deal_next_street(poker, :river, 1)

  defp advance_street_or_showdown(%{street: :river} = poker), do: showdown(poker)

  defp deal_next_street(poker, street, count) do
    {cards, deck} = Enum.split(poker.deck, count)

    seats =
      Map.new(poker.seats, fn {i, s} -> {i, %{s | contributed_this_street: 0, acted?: false}} end)

    poker = %{
      poker
      | deck: deck,
        community_cards: poker.community_cards ++ cards,
        street: street,
        current_bet: 0,
        min_raise: poker.big_blind,
        seats: seats
    }

    occupied = occupied_seats(poker)

    if count_active(poker) == 0 do
      %{poker | action_on: nil} |> advance_street_or_showdown()
    else
      start = next_seat_clockwise(occupied, poker.button_seat)
      %{poker | action_on: find_active_from(poker, start, occupied)}
    end
  end

  # Every seat but one folded: that seat wins everything without a
  # showdown. Numerically the winner ends up with the full pot either way,
  # but any portion of their own bet that nobody could call is tracked
  # separately as `uncalled_return` purely so the UI can say "returned"
  # rather than "won" for that slice.
  defp settle_uncontested(poker) do
    [winner] =
      poker.seats |> Enum.filter(fn {_i, s} -> s.status != :folded end) |> Enum.map(&elem(&1, 0))

    total_contributed =
      poker.seats |> Map.values() |> Enum.map(& &1.total_contributed) |> Enum.sum()

    second_highest =
      poker.seats
      |> Enum.reject(fn {i, _s} -> i == winner end)
      |> Enum.map(fn {_i, s} -> s.total_contributed end)
      |> Enum.max(fn -> 0 end)

    winner_contributed = Map.fetch!(poker.seats, winner).total_contributed
    uncalled = max(0, winner_contributed - second_highest)

    poker
    |> update_seat(winner, fn s -> %{s | stack: s.stack + total_contributed} end)
    |> Map.put(:status, :hand_over)
    |> Map.put(:action_on, nil)
    |> Map.put(:pots, [
      %{
        amount: total_contributed - uncalled,
        eligible: [winner],
        winners: [winner],
        award_each: total_contributed - uncalled,
        extra_chip_winners: []
      }
    ])
    |> Map.put(
      :uncalled_return,
      if(uncalled > 0, do: %{seat: winner, amount: uncalled}, else: nil)
    )
  end

  # Builds one pot per distinct contribution tier (the classic side-pot
  # algorithm: every seat that put in at least the tier's amount - folded
  # seats included, since their chips still count toward the pot even
  # though they can't win it - contributes to that tier), then awards each
  # pot to whichever *live* eligible seat(s) hold the best hand, splitting
  # ties with any odd chip going to the seat(s) closest left of the button.
  defp showdown(poker) do
    levels =
      poker.seats
      |> Map.values()
      |> Enum.map(& &1.total_contributed)
      |> Enum.reject(&(&1 == 0))
      |> Enum.uniq()
      |> Enum.sort()

    {pots, _} =
      Enum.reduce(levels, {[], 0}, fn level, {pots, previous_level} ->
        contributors = poker.seats |> Enum.filter(fn {_i, s} -> s.total_contributed >= level end)
        amount = (level - previous_level) * length(contributors)

        eligible =
          contributors
          |> Enum.filter(fn {_i, s} -> s.status != :folded end)
          |> Enum.map(&elem(&1, 0))

        pot = %{
          amount: amount,
          eligible: eligible,
          winners: nil,
          award_each: nil,
          extra_chip_winners: nil
        }

        {pots ++ [pot], level}
      end)

    {pots, seats} = Enum.map_reduce(pots, poker.seats, &award_pot(&1, &2, poker))

    poker
    |> Map.put(:seats, seats)
    |> Map.put(:status, :hand_over)
    |> Map.put(:action_on, nil)
    |> Map.put(:pots, pots)
  end

  defp award_pot(%{amount: amount, eligible: eligible} = pot, seats, poker) do
    ranked =
      Enum.map(eligible, fn seat_index ->
        seat = Map.fetch!(seats, seat_index)
        {seat_index, HandEvaluator.rank(seat.hole_cards ++ poker.community_cards)}
      end)

    best_rank = ranked |> Enum.map(&elem(&1, 1)) |> Enum.max()

    winners =
      ranked |> Enum.filter(fn {_i, rank} -> rank == best_rank end) |> Enum.map(&elem(&1, 0))

    award_each = div(amount, length(winners))
    remainder = rem(amount, length(winners))

    ordered_winners = order_from_button(winners, poker.button_seat, occupied_seats(poker))
    extra_chip_winners = Enum.take(ordered_winners, remainder)

    seats =
      Enum.reduce(winners, seats, fn seat_index, seats ->
        extra = if seat_index in extra_chip_winners, do: 1, else: 0
        Map.update!(seats, seat_index, &%{&1 | stack: &1.stack + award_each + extra})
      end)

    {%{pot | winners: winners, award_each: award_each, extra_chip_winners: extra_chip_winners},
     seats}
  end

  # Orders seats by clockwise distance from the seat left of the button -
  # the traditional order for handing out an odd leftover chip.
  defp order_from_button(seats, button_seat, occupied) do
    start = next_seat_clockwise(occupied, button_seat)
    idx = Enum.find_index(occupied, &(&1 == start)) || 0
    {before, from} = Enum.split(occupied, idx)
    ordered_occupied = from ++ before
    Enum.filter(ordered_occupied, &(&1 in seats))
  end

  defp occupied_seats(poker), do: poker.seats |> Map.keys() |> Enum.sort()

  defp next_seat_clockwise(occupied, from) do
    Enum.find(occupied, &(&1 > from)) || hd(occupied)
  end

  # Walks the occupied seats clockwise starting at (and including) `start`,
  # returning the first with an active seat still able to act, or `nil` if
  # every remaining seat is already folded/all-in.
  defp find_active_from(poker, start, occupied) do
    idx = Enum.find_index(occupied, &(&1 == start)) || 0
    {before, from} = Enum.split(occupied, idx)
    ordered = from ++ before
    Enum.find(ordered, &(Map.fetch!(poker.seats, &1).status == :active))
  end

  defp live_count(poker), do: poker.seats |> Map.values() |> Enum.count(&(&1.status != :folded))
  defp count_active(poker), do: poker.seats |> Map.values() |> Enum.count(&(&1.status == :active))

  defp all_settled?(poker) do
    poker.seats
    |> Map.values()
    |> Enum.filter(&(&1.status == :active))
    |> Enum.all?(&(&1.acted? and &1.contributed_this_street == poker.current_bet))
  end

  defp build_deck, do: for(rank <- @ranks, suit <- @suits, do: rank <> suit)
end
