defmodule HighSociety.Games.PokerTest do
  use ExUnit.Case, async: true

  alias HighSociety.Games.Poker

  defp new_seat(attrs) do
    Map.merge(
      %{
        user_id: 1,
        username: "player",
        hole_cards: [],
        stack: 100,
        status: :active,
        contributed_this_street: 0,
        total_contributed: 0,
        acted?: false
      },
      Map.new(attrs)
    )
  end

  defp occupied_seats(count, opts \\ []) do
    stack = Keyword.get(opts, :stack, 100)

    0..(count - 1)
    |> Enum.map(fn i -> {i, %{user_id: i + 1, username: "player#{i}", stack: stack}} end)
    |> Map.new()
  end

  describe "start_hand/4" do
    test "deals two unique cards to each seat and posts blinds heads-up" do
      seats = occupied_seats(2)
      poker = Poker.start_hand(seats, 0, 5, 10)

      all_cards = poker.seats |> Map.values() |> Enum.flat_map(& &1.hole_cards)
      assert length(all_cards) == 4
      assert length(Enum.uniq(all_cards)) == 4

      # heads-up: the button posts the small blind and acts first preflop
      assert poker.seats[0].contributed_this_street == 5
      assert poker.seats[1].contributed_this_street == 10
      assert poker.current_bet == 10
      assert poker.action_on == 0
    end

    test "3+ players: blinds pass clockwise from the button and UTG acts first" do
      seats = occupied_seats(3)
      poker = Poker.start_hand(seats, 0, 5, 10)

      assert poker.seats[1].contributed_this_street == 5
      assert poker.seats[2].contributed_this_street == 10
      assert poker.seats[0].contributed_this_street == 0
      assert poker.current_bet == 10
      assert poker.action_on == 0
    end

    test "a blind posted short of the full amount goes all-in for whatever's left" do
      seats = occupied_seats(2) |> put_in([0, :stack], 3)
      poker = Poker.start_hand(seats, 0, 5, 10)

      assert poker.seats[0].contributed_this_street == 3
      assert poker.seats[0].status == :all_in
      assert poker.seats[0].stack == 0
    end
  end

  describe "an uncontested fold" do
    test "awards the whole pot, tracking any uncalled raise separately for display" do
      poker = %Poker{
        seats: %{
          0 =>
            new_seat(
              user_id: 1,
              stack: 78,
              contributed_this_street: 22,
              total_contributed: 22,
              acted?: true
            ),
          1 => new_seat(user_id: 2, stack: 98, contributed_this_street: 2, total_contributed: 2)
        },
        button_seat: 0,
        action_on: 1,
        current_bet: 22,
        min_raise: 20,
        street: :turn,
        small_blind: 1,
        big_blind: 2
      }

      assert {:ok, result} = Poker.fold(poker, 1)
      assert result.status == :hand_over
      assert result.seats[0].stack == 78 + 24
      assert result.uncalled_return == %{seat: 0, amount: 20}
      assert [pot] = result.pots
      assert pot.amount == 4
      assert pot.winners == [0]
    end
  end

  describe "side pots" do
    test "a short all-in creates a separate pot the short stack isn't eligible for" do
      poker = %Poker{
        seats: %{
          0 =>
            new_seat(
              user_id: 1,
              hole_cards: ~w(AS AD),
              stack: 10,
              contributed_this_street: 0,
              total_contributed: 0
            ),
          1 =>
            new_seat(
              user_id: 2,
              hole_cards: ~w(KS KD),
              stack: 49,
              contributed_this_street: 1,
              total_contributed: 1
            ),
          2 =>
            new_seat(
              user_id: 3,
              hole_cards: ~w(QS QD),
              stack: 48,
              contributed_this_street: 2,
              total_contributed: 2
            )
        },
        button_seat: 0,
        deck: ~w(2S 6D 9C JH 4H),
        street: :preflop,
        status: :in_progress,
        small_blind: 1,
        big_blind: 2,
        current_bet: 2,
        min_raise: 2,
        action_on: 0
      }

      # seat 0 shoves its whole (short) stack, both others call
      {:ok, poker} = Poker.raise(poker, 0, 10)
      {:ok, poker} = Poker.call(poker, 1)
      {:ok, poker} = Poker.call(poker, 2)
      assert poker.street == :flop
      assert poker.action_on == 1

      # seat 0 is all-in and can't act again; 1 and 2 keep betting between themselves
      {:ok, poker} = Poker.bet(poker, 1, 20)
      {:ok, poker} = Poker.call(poker, 2)
      assert poker.street == :turn

      {:ok, poker} = Poker.check(poker, 1)
      {:ok, poker} = Poker.check(poker, 2)
      assert poker.street == :river

      {:ok, poker} = Poker.check(poker, 1)
      {:ok, poker} = Poker.check(poker, 2)

      assert poker.status == :hand_over
      # pair of aces (seat 0) beats pair of kings (seat 1) beats pair of queens (seat 2)
      assert poker.seats[0].stack == 30
      assert poker.seats[1].stack == 60
      assert poker.seats[2].stack == 20
      assert Enum.sum(Enum.map(poker.seats, fn {_i, s} -> s.stack end)) == 110

      assert [pot1, pot2] = poker.pots
      assert pot1.amount == 30
      assert pot1.eligible == [0, 1, 2]
      assert pot1.winners == [0]
      assert pot2.amount == 40
      assert pot2.eligible == [1, 2]
      assert pot2.winners == [1]
    end
  end

  describe "action legality" do
    setup do
      poker = %Poker{
        seats: %{
          0 => new_seat(user_id: 1, stack: 100),
          1 => new_seat(user_id: 2, stack: 100, contributed_this_street: 2, total_contributed: 2)
        },
        button_seat: 0,
        action_on: 0,
        current_bet: 2,
        min_raise: 2,
        street: :preflop,
        small_blind: 1,
        big_blind: 2
      }

      %{poker: poker}
    end

    test "acting out of turn is always rejected", %{poker: poker} do
      assert {:error, :not_your_turn} = Poker.check(poker, 1)
      assert {:error, :not_your_turn} = Poker.fold(poker, 1)
      assert {:error, :not_your_turn} = Poker.call(poker, 1)
      assert {:error, :not_your_turn} = Poker.bet(poker, 1, 10)
      assert {:error, :not_your_turn} = Poker.raise(poker, 1, 10)
    end

    test "can't check with a bet outstanding", %{poker: poker} do
      assert {:error, :bet_outstanding} = Poker.check(poker, 0)
    end

    test "can't bet when a bet is already outstanding", %{poker: poker} do
      assert {:error, :bet_already_outstanding} = Poker.bet(poker, 0, 10)
    end

    test "can't raise below the minimum raise increment", %{poker: poker} do
      assert {:error, :below_minimum_raise} = Poker.raise(poker, 0, 3)
    end

    test "can raise all-in for less than the minimum increment", %{poker: poker} do
      poker = put_in(poker.seats[0].stack, 3)
      assert {:ok, result} = Poker.raise(poker, 0, 3)
      assert result.seats[0].status == :all_in
    end

    test "can't raise to less than the current bet", %{poker: poker} do
      assert {:error, :must_exceed_current_bet} = Poker.raise(poker, 0, 2)
    end
  end

  describe "timeout/2" do
    test "checks when checking is legal" do
      poker = %Poker{
        seats: %{
          0 => new_seat(user_id: 1, contributed_this_street: 2),
          1 => new_seat(user_id: 2, contributed_this_street: 2)
        },
        action_on: 0,
        current_bet: 2,
        street: :flop
      }

      result = Poker.timeout(poker, 0)
      assert result.seats[0].acted?
      assert result.action_on == 1
    end

    test "folds when there's a bet to call" do
      poker = %Poker{
        seats: %{
          0 => new_seat(user_id: 1, contributed_this_street: 0),
          1 => new_seat(user_id: 2, contributed_this_street: 10)
        },
        action_on: 0,
        current_bet: 10,
        street: :flop
      }

      result = Poker.timeout(poker, 0)
      assert result.status == :hand_over
      assert result.seats[0].status == :folded
    end

    test "is a safe no-op when the seat isn't actually on the action" do
      poker = %Poker{
        seats: %{0 => new_seat(user_id: 1), 1 => new_seat(user_id: 2)},
        action_on: 1,
        current_bet: 0,
        street: :flop
      }

      assert Poker.timeout(poker, 0) == poker
    end
  end

  describe "force_fold/2" do
    test "leaves the action untouched when it wasn't the leaving seat's turn" do
      poker = %Poker{
        seats: %{
          0 => new_seat(user_id: 1),
          1 => new_seat(user_id: 2),
          2 => new_seat(user_id: 3)
        },
        action_on: 2,
        current_bet: 0,
        street: :flop
      }

      result = Poker.force_fold(poker, 0)
      assert result.status == :in_progress
      assert result.action_on == 2
      assert result.seats[0].status == :folded
    end

    test "settles immediately if it leaves only one seat standing, even when it wasn't that seat's turn" do
      poker = %Poker{
        seats: %{
          0 => new_seat(user_id: 1, stack: 50, total_contributed: 50, status: :folded),
          1 => new_seat(user_id: 2, stack: 50, total_contributed: 50),
          2 => new_seat(user_id: 3, stack: 50, total_contributed: 50)
        },
        action_on: 2,
        current_bet: 0,
        street: :flop
      }

      result = Poker.force_fold(poker, 1)
      assert result.status == :hand_over
      assert result.seats[2].stack == 200
    end
  end
end
