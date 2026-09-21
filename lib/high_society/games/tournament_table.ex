defmodule HighSociety.Games.TournamentTable do
  @moduledoc """
  One GenServer per live tournament table, registered under
  `HighSociety.Games.TournamentRegistry` (tagged `{:table, slug}`) -
  created and destroyed at runtime by `HighSociety.Games.TournamentCoordinator`
  (initial seating, late-join overflow, rebalancing), never by a player.
  Closely mirrors `HighSociety.Games.PokerTable`'s hand-lifecycle/timeout/
  persistence shape (deliberately not sharing code with it - same spirit
  as this codebase's several parallel, non-abstracted solo-game modules),
  with three real differences:

    * Seats are never player-initiated. `seat_transfer/5` (idempotent by
      `move_id`) is the only way a seat fills, and `mark_for_removal/2`
      only ever *marks* a seat for removal - the actual removal happens
      automatically, at the next hand-over, so a rebalance move can never
      disrupt a hand in progress.
    * Blinds and the tournament-wide break flag live in local state and
      are pushed here by `set_blinds/4`/`set_on_break/2` casts from the
      coordinator - never a synchronous call, which would turn the
      coordinator into a bottleneck across every table's every hand.
      `start_new_hand/1` reads them fresh, exactly like `PokerTable` reads
      `config.small_blind` today.
    * A hand-over that leaves the table with zero seats (every remaining
      occupant either busted or was marked for removal) closes the table:
      persists `status: "closed"` and stops with reason `:normal`, which
      `HighSociety.Games.TournamentTablesSupervisor`'s `restart: :transient`
      child spec respects (never restarted) - the same mechanism
      `HighSociety.Games.BattleshipMatch` uses to end a finished match.

  Busting is a *batch* event, computed once per hand-over (never once per
  eliminated seat - two players can bust in the same hand, and that
  merge already happens inside one serialized callback), cast to the
  owning `HighSociety.Games.TournamentCoordinator` as
  `{:eliminations, slug, [%{user_id, username, stack_before_hand}, ...]}`
  so it can assign `finish_place` fairly (shorter pre-hand stack gets the
  worse placement).

  Durable state (seats, button, in-progress hand) persists to a
  `HighSociety.Games.TournamentTableState` row after every change, same
  as cash tables. Blinds/break/pending-removals are deliberately *not*
  persisted - a restarted table re-derives current blinds/break from the
  tournament's own row (see `put_current_blinds/1`), the same one source
  of truth the coordinator itself uses, rather than trusting a possibly
  stale local copy.
  """
  use GenServer

  alias HighSociety.Games.Poker
  alias HighSociety.Games.PokerTables
  alias HighSociety.Games.TournamentTableState
  alias HighSociety.Games.TournamentTablesSupervisor
  alias HighSociety.Repo
  alias HighSociety.Tournaments.PokerTournament

  @action_seconds 20
  @hand_over_pause_ms 7_000

  ## Public API

  def start_link(table_config),
    do: GenServer.start_link(__MODULE__, table_config, name: via(table_config.slug))

  def via(slug), do: {:via, Registry, {HighSociety.Games.TournamentRegistry, {:table, slug}}}

  defp coordinator_via(tournament_id),
    do: {:via, Registry, {HighSociety.Games.TournamentRegistry, {:coordinator, tournament_id}}}

  @doc "The PubSub topic a table's updates are broadcast on."
  def topic(slug), do: "tournament_table:#{slug}"

  @doc """
  Creates a fresh, empty, `active` row for `tournament_id` at `slug` and
  starts its GenServer - the row must exist before the process starts
  (mirrors `HighSociety.Games.BattleshipMatch.create/2`), so both this and
  the boot-time rehydration sweep are just "start a child for a slug
  whose row already exists."
  """
  @spec create!(pos_integer(), String.t()) :: DynamicSupervisor.on_start_child()
  def create!(tournament_id, slug) do
    %TournamentTableState{}
    |> TournamentTableState.changeset(%{
      slug: slug,
      tournament_id: tournament_id,
      status: "active"
    })
    |> Repo.insert!()

    TournamentTablesSupervisor.start_table(%{slug: slug, tournament_id: tournament_id})
  end

  @doc """
  Seats `user_id` (with `username`/`stack`) at the first open seat -
  called only by `TournamentCoordinator` (initial seating, late-join,
  rebalancing), never by a player directly. Idempotent by `move_id`: a
  retried call for a move already applied just returns the current state.
  """
  def seat_transfer(slug, move_id, user_id, username, stack),
    do: GenServer.call(via(slug), {:seat_transfer, move_id, user_id, username, stack})

  @doc """
  Marks `user_id`'s seat to be freed the next time the table's current
  hand ends (never mid-hand) - used by the coordinator to relocate a
  player during rebalancing. Always succeeds immediately; the removal,
  and the `{:seats_freed, slug, [...]}` confirmation cast back to the
  coordinator, happen inside the table's own hand-over processing.
  """
  def mark_for_removal(slug, user_id), do: GenServer.cast(via(slug), {:mark_for_removal, user_id})

  @doc "Pushes new blinds for `level`, applied to the next hand this table deals."
  def set_blinds(slug, small_blind, big_blind, level),
    do: GenServer.cast(via(slug), {:set_blinds, small_blind, big_blind, level})

  @doc "Pushes the tournament-wide break flag - gates new hands starting while true."
  def set_on_break(slug, on_break?), do: GenServer.cast(via(slug), {:set_on_break, on_break?})

  @doc "Takes `action` (`:check`, `:fold`, `:call`, `:bet`, `:raise`) for `user_id`'s seat."
  def act(slug, user_id, action, amount \\ nil),
    do: GenServer.call(via(slug), {:act, user_id, action, amount})

  @doc "Reveals `user_id`'s hole cards after a hand they won ends, instead of staying mucked. See `Poker.reveal_hand/2`."
  def reveal_hand(slug, user_id), do: GenServer.call(via(slug), {:reveal_hand, user_id})

  @doc "The table's current public state."
  def get_state(slug), do: GenServer.call(via(slug), :get_state)

  ## Callbacks

  @impl true
  def init(%{slug: slug, tournament_id: tournament_id}) do
    Process.set_label({:tournament_table, slug})

    # See `HighSociety.Games.PokerTable.init/1` for the atom-interning
    # reason this comes first. Unlike `PokerTable`, this process is never
    # a static boot-time child (only ever created live, or from a
    # detached, unlinked boot-time rehydration `Task` - see
    # `TournamentTablesSupervisor.rehydrate_in_flight_tables!/0` and
    # `HighSociety.Games.BattleshipMatch.init/1`'s identical reasoning),
    # so there's no boot-ordering/test-sandbox race to guard against here.
    Code.ensure_loaded!(Poker)
    row = Repo.get_by!(TournamentTableState, slug: slug)

    if row.status == "closed" do
      :ignore
    else
      state = row |> from_row(tournament_id) |> put_current_blinds() |> catch_up()
      if state.status == "closed", do: :ignore, else: {:ok, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, public_view(state), state}

  def handle_call({:seat_transfer, move_id, user_id, username, stack}, _from, state) do
    cond do
      MapSet.member?(state.applied_moves, move_id) or already_seated?(state, user_id) ->
        {:reply, {:ok, public_view(state)}, state}

      true ->
        case open_seat_index(state.seats) do
          nil ->
            {:reply, {:error, :table_full}, state}

          seat_index ->
            entry = %{user_id: user_id, username: username, stack: stack}

            state = %{
              state
              | seats: Map.put(state.seats, seat_index, entry),
                applied_moves: MapSet.put(state.applied_moves, move_id)
            }

            state = maybe_start_hand(state)
            reply_result(state, {:ok, public_view(state)})
        end
    end
  end

  def handle_call({:act, user_id, action, amount}, _from, state) do
    case find_seat(state, user_id) do
      nil ->
        {:reply, {:error, :not_seated}, state}

      seat_index ->
        case state.hand do
          nil ->
            {:reply, {:error, :no_hand_in_progress}, state}

          hand ->
            case dispatch_action(hand, seat_index, action, amount) do
              {:ok, new_hand} ->
                last_action = last_action(seat_index, action, new_hand)
                state = apply_hand_result(state, new_hand)
                reply_result(state, {:ok, public_view(state, last_action)}, last_action)

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end
        end
    end
  end

  def handle_call({:reveal_hand, user_id}, _from, state) do
    case find_seat(state, user_id) do
      nil ->
        {:reply, {:error, :not_seated}, state}

      seat_index ->
        case state.hand do
          nil ->
            {:reply, {:error, :no_hand_in_progress}, state}

          hand ->
            case Poker.reveal_hand(hand, seat_index) do
              {:ok, new_hand} ->
                # Unlike `:act`, no `apply_hand_result` - revealing doesn't
                # change `status`, merge stacks, or touch the already-running
                # `:start_next_hand` timer.
                state = %{state | hand: new_hand}
                reply_result(state, {:ok, public_view(state)})

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end
        end
    end
  end

  @impl true
  def handle_cast({:mark_for_removal, user_id}, state),
    do: {:noreply, %{state | pending_removals: MapSet.put(state.pending_removals, user_id)}}

  def handle_cast({:set_blinds, small_blind, big_blind, level}, state) do
    state = %{state | small_blind: small_blind, big_blind: big_blind, level: level}
    broadcast(state)
    {:noreply, state}
  end

  def handle_cast({:set_on_break, on_break?}, state) do
    state = %{state | on_break: on_break?}
    broadcast(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:action_timeout, seat_index, hand_ref}, state) do
    if (hand_ref == state.hand_ref and state.hand) && state.hand.action_on == seat_index do
      seat = Map.fetch!(state.hand.seats, seat_index)
      action = if seat.contributed_this_street == state.hand.current_bet, do: :check, else: :fold

      new_hand = Poker.timeout(state.hand, seat_index)
      last_action = %{seat: seat_index, action: action, all_in: false}
      state = apply_hand_result(state, new_hand)
      noreply_result(state, last_action)
    else
      {:noreply, state}
    end
  end

  def handle_info({:start_next_hand, hand_ref}, state) do
    if hand_ref == state.hand_ref do
      state = maybe_start_hand_after_pause(state)
      noreply_result(state)
    else
      {:noreply, state}
    end
  end

  ## Seating

  defp already_seated?(state, user_id),
    do: Enum.any?(state.seats, fn {_i, s} -> s.user_id == user_id end)

  defp open_seat_index(seats),
    do: Enum.find(0..(PokerTables.seats() - 1), &(not Map.has_key?(seats, &1)))

  defp find_seat(state, user_id) do
    case Enum.find(state.seats, fn {_i, s} -> s.user_id == user_id end) do
      nil -> nil
      {seat_index, _seat} -> seat_index
    end
  end

  ## Hand lifecycle

  defp maybe_start_hand(%{hand: nil, seats: seats, on_break: false} = state)
       when map_size(seats) >= 2,
       do: start_new_hand(state)

  defp maybe_start_hand(state), do: state

  defp maybe_start_hand_after_pause(%{seats: seats, on_break: false} = state)
       when map_size(seats) >= 2,
       do: start_new_hand(state)

  defp maybe_start_hand_after_pause(state), do: %{state | hand: nil}

  defp start_new_hand(state) do
    occupied = state.seats |> Map.keys() |> Enum.sort()
    button_seat = next_button_seat(state.button_seat, occupied)
    hand = Poker.start_hand(state.seats, button_seat, state.small_blind, state.big_blind)
    state = %{state | button_seat: button_seat, hand_ref: state.hand_ref + 1}
    apply_hand_result(state, hand)
  end

  defp next_button_seat(nil, occupied), do: hd(occupied)

  defp next_button_seat(previous, occupied),
    do: Enum.find(occupied, &(&1 > previous)) || hd(occupied)

  ## Actions

  defp dispatch_action(hand, seat, :check, _amount), do: Poker.check(hand, seat)
  defp dispatch_action(hand, seat, :fold, _amount), do: Poker.fold(hand, seat)
  defp dispatch_action(hand, seat, :call, _amount), do: Poker.call(hand, seat)
  defp dispatch_action(hand, seat, :bet, amount), do: Poker.bet(hand, seat, amount)
  defp dispatch_action(hand, seat, :raise, amount), do: Poker.raise(hand, seat, amount)

  defp last_action(seat, action, new_hand) when action in [:call, :bet, :raise],
    do: %{seat: seat, action: action, all_in: match?(%{stack: 0}, new_hand.seats[seat])}

  defp last_action(seat, action, _new_hand), do: %{seat: seat, action: action, all_in: false}

  # Applies the result of any hand-mutating action (a player's action, a
  # timeout forfeit, or a fresh deal). On `hand_over`, merges every seat's
  # stack back into the durable seat map - splitting departures into
  # eliminations (stack <= 0) and rebalance-driven removals
  # (`pending_removals`), notifying the coordinator of both as one batch
  # each - and either schedules the next hand's pause or, if that leaves
  # zero seats, marks the table `closed` so `finalize/1` stops it.
  # Otherwise schedules a fresh action-clock timeout.
  defp apply_hand_result(state, new_hand) do
    state = cancel_timer(state)

    if new_hand.status == :hand_over do
      {seats, eliminated, freed} =
        merge_hand_stacks(state.seats, new_hand, state.pending_removals)

      notify_eliminations(state, eliminated)
      notify_seats_freed(state, freed)

      state = %{
        state
        | seats: seats,
          pending_removals: MapSet.new(),
          hand: new_hand,
          action_deadline: nil
      }

      if map_size(seats) == 0 do
        %{state | status: "closed"}
      else
        timer_ref =
          Process.send_after(self(), {:start_next_hand, state.hand_ref}, @hand_over_pause_ms)

        %{state | timer_ref: timer_ref}
      end
    else
      deadline = DateTime.add(DateTime.utc_now(), @action_seconds, :second)

      timer_ref =
        Process.send_after(
          self(),
          {:action_timeout, new_hand.action_on, state.hand_ref},
          @action_seconds * 1000
        )

      %{state | hand: new_hand, action_deadline: deadline, timer_ref: timer_ref}
    end
  end

  defp merge_hand_stacks(durable_seats, %Poker{seats: hand_seats}, pending_removals) do
    Enum.reduce(hand_seats, {durable_seats, [], []}, fn {i, hand_seat},
                                                        {seats, eliminated, freed} ->
      case Map.get(seats, i) do
        nil ->
          {seats, eliminated, freed}

        durable_seat ->
          cond do
            hand_seat.stack <= 0 ->
              bust = %{
                user_id: durable_seat.user_id,
                username: durable_seat.username,
                stack_before_hand: durable_seat.stack
              }

              {Map.delete(seats, i), [bust | eliminated], freed}

            MapSet.member?(pending_removals, durable_seat.user_id) ->
              freed_seat = %{user_id: durable_seat.user_id, stack: hand_seat.stack}
              {Map.delete(seats, i), eliminated, [freed_seat | freed]}

            true ->
              {Map.put(seats, i, %{durable_seat | stack: hand_seat.stack}), eliminated, freed}
          end
      end
    end)
  end

  defp notify_eliminations(_state, []), do: :ok

  defp notify_eliminations(state, eliminated) do
    GenServer.cast(coordinator_via(state.tournament_id), {:eliminations, state.slug, eliminated})
  end

  defp notify_seats_freed(_state, []), do: :ok

  defp notify_seats_freed(state, freed) do
    GenServer.cast(coordinator_via(state.tournament_id), {:seats_freed, state.slug, freed})
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end

  ## Crash recovery

  defp put_current_blinds(state) do
    tournament = Repo.get!(PokerTournament, state.tournament_id)
    level = Enum.at(tournament.blind_levels, tournament.current_level - 1)

    %{
      state
      | small_blind: level["small_blind"],
        big_blind: level["big_blind"],
        level: tournament.current_level,
        on_break: tournament.on_break
    }
  end

  defp catch_up(%{status: "closed"} = state), do: state
  defp catch_up(%{hand: nil} = state), do: state

  defp catch_up(%{hand: %{status: :hand_over}} = state) do
    state = maybe_start_hand_after_pause(state)
    persist(state)
    state
  end

  # See `PokerTable.catch_up/1` for why an in-progress hand never has
  # `action_on: nil` unless the run-out is already fully resolved and
  # simply waiting on the next street's cards.
  defp catch_up(%{hand: %{status: :in_progress, action_on: nil}} = state), do: state

  defp catch_up(%{hand: %{status: :in_progress}} = state) do
    now = DateTime.utc_now()

    overdue? =
      is_nil(state.action_deadline) or DateTime.compare(state.action_deadline, now) == :lt

    if overdue? do
      new_hand = Poker.timeout(state.hand, state.hand.action_on)
      state = apply_hand_result(state, new_hand)
      persist(state)
      state
    else
      remaining_ms = state.action_deadline |> DateTime.diff(now, :millisecond) |> max(0)

      timer_ref =
        Process.send_after(
          self(),
          {:action_timeout, state.hand.action_on, state.hand_ref},
          remaining_ms
        )

      %{state | timer_ref: timer_ref}
    end
  end

  defp from_row(row, tournament_id) do
    wrapper = row.hand

    %{
      slug: row.slug,
      tournament_id: tournament_id,
      status: row.status,
      seats: seats_row_from_json(row.seats),
      button_seat: row.button_seat,
      hand: wrapper && hand_from_json(wrapper["poker"]),
      hand_ref: (wrapper && wrapper["hand_ref"]) || 0,
      action_deadline:
        wrapper && wrapper["action_deadline"] && parse_iso8601(wrapper["action_deadline"]),
      timer_ref: nil,
      small_blind: 0,
      big_blind: 0,
      level: 1,
      on_break: false,
      pending_removals: MapSet.new(),
      applied_moves: MapSet.new()
    }
  end

  ## Persistence + broadcast

  # `finalize/1` is the one chokepoint that decides whether this table
  # keeps running or has just closed (see `apply_hand_result/2`) - every
  # caller converts its `{:cont, state} | {:stop, :normal, state}` into
  # the right GenServer return, mirroring
  # `HighSociety.Games.BattleshipMatch`'s identical `:stop` shape for
  # ending a match cleanly.
  defp finalize(state, last_action) do
    persist(state)
    broadcast(state, last_action)
    if state.status == "closed", do: {:stop, :normal, state}, else: {:cont, state}
  end

  defp reply_result(state, reply, last_action \\ nil) do
    case finalize(state, last_action) do
      {:stop, :normal, state} -> {:stop, :normal, reply, state}
      {:cont, state} -> {:reply, reply, state}
    end
  end

  defp noreply_result(state, last_action \\ nil) do
    case finalize(state, last_action) do
      {:stop, :normal, state} -> {:stop, :normal, state}
      {:cont, state} -> {:noreply, state}
    end
  end

  defp persist(state) do
    now = DateTime.utc_now(:second)

    %TournamentTableState{}
    |> TournamentTableState.changeset(%{
      slug: state.slug,
      tournament_id: state.tournament_id,
      status: state.status,
      seats: seats_row_to_json(state.seats),
      button_seat: state.button_seat,
      hand: hand_wrapper_to_json(state)
    })
    |> Ecto.Changeset.put_change(:inserted_at, now)
    |> Ecto.Changeset.put_change(:updated_at, now)
    |> Repo.insert!(
      on_conflict: {:replace, [:seats, :button_seat, :hand, :status, :updated_at]},
      conflict_target: :slug
    )
  end

  defp broadcast(state, last_action \\ nil) do
    Phoenix.PubSub.broadcast(
      HighSociety.PubSub,
      topic(state.slug),
      {:tournament_table_updated, public_view(state, last_action)}
    )
  end

  defp public_view(state, last_action \\ nil) do
    %{
      slug: state.slug,
      tournament_id: state.tournament_id,
      seats: state.seats,
      button_seat: state.button_seat,
      hand: state.hand,
      action_deadline: state.action_deadline,
      small_blind: state.small_blind,
      big_blind: state.big_blind,
      level: state.level,
      on_break: state.on_break,
      last_action: last_action
    }
  end

  ## JSON (de)serialization - identical shape/boundary convention to
  ## `HighSociety.Games.PokerTable`'s.

  defp seats_row_to_json(seats) do
    for i <- 0..(PokerTables.seats() - 1) do
      case Map.get(seats, i) do
        nil ->
          nil

        %{user_id: user_id, username: username, stack: stack} ->
          %{"user_id" => user_id, "username" => username, "stack" => stack}
      end
    end
  end

  defp seats_row_from_json(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn
      {nil, _i}, acc ->
        acc

      {%{"user_id" => user_id, "username" => username, "stack" => stack}, i}, acc ->
        Map.put(acc, i, %{user_id: user_id, username: username, stack: stack})
    end)
  end

  defp hand_wrapper_to_json(%{hand: nil}), do: nil

  defp hand_wrapper_to_json(%{hand: hand, action_deadline: deadline, hand_ref: hand_ref}) do
    %{
      "poker" => hand_to_json(hand),
      "action_deadline" => deadline && DateTime.to_iso8601(deadline),
      "hand_ref" => hand_ref
    }
  end

  defp hand_to_json(%Poker{} = poker) do
    %{
      "seats" => Map.new(poker.seats, fn {i, s} -> {Integer.to_string(i), seat_to_json(s)} end),
      "button_seat" => poker.button_seat,
      "deck" => poker.deck,
      "community_cards" => poker.community_cards,
      "street" => Atom.to_string(poker.street),
      "status" => Atom.to_string(poker.status),
      "small_blind" => poker.small_blind,
      "big_blind" => poker.big_blind,
      "current_bet" => poker.current_bet,
      "min_raise" => poker.min_raise,
      "action_on" => poker.action_on,
      "pots" => poker.pots && Enum.map(poker.pots, &pot_to_json/1),
      "uncalled_return" =>
        poker.uncalled_return &&
          Map.new(poker.uncalled_return, fn {k, v} -> {Atom.to_string(k), v} end),
      "revealed_seats" => poker.revealed_seats
    }
  end

  defp seat_to_json(s) do
    %{
      "user_id" => s.user_id,
      "username" => s.username,
      "hole_cards" => s.hole_cards,
      "stack" => s.stack,
      "status" => Atom.to_string(s.status),
      "contributed_this_street" => s.contributed_this_street,
      "total_contributed" => s.total_contributed,
      "acted?" => s.acted?
    }
  end

  defp pot_to_json(pot) do
    %{
      "amount" => pot.amount,
      "eligible" => pot.eligible,
      "winners" => pot.winners,
      "award_each" => pot.award_each,
      "extra_chip_winners" => pot.extra_chip_winners
    }
  end

  defp hand_from_json(%{} = h) do
    %Poker{
      seats: Map.new(h["seats"], fn {i, s} -> {String.to_integer(i), seat_from_json(s)} end),
      button_seat: h["button_seat"],
      deck: h["deck"],
      community_cards: h["community_cards"],
      street: String.to_existing_atom(h["street"]),
      status: String.to_existing_atom(h["status"]),
      small_blind: h["small_blind"],
      big_blind: h["big_blind"],
      current_bet: h["current_bet"],
      min_raise: h["min_raise"],
      action_on: h["action_on"],
      pots: h["pots"] && Enum.map(h["pots"], &pot_from_json/1),
      uncalled_return:
        h["uncalled_return"] &&
          %{seat: h["uncalled_return"]["seat"], amount: h["uncalled_return"]["amount"]},
      revealed_seats: h["revealed_seats"] || []
    }
  end

  defp seat_from_json(s) do
    %{
      user_id: s["user_id"],
      username: s["username"],
      hole_cards: s["hole_cards"],
      stack: s["stack"],
      status: String.to_existing_atom(s["status"]),
      contributed_this_street: s["contributed_this_street"],
      total_contributed: s["total_contributed"],
      acted?: s["acted?"]
    }
  end

  defp pot_from_json(p) do
    %{
      amount: p["amount"],
      eligible: p["eligible"],
      winners: p["winners"],
      award_each: p["award_each"],
      extra_chip_winners: p["extra_chip_winners"]
    }
  end

  defp parse_iso8601(str) do
    {:ok, datetime, _offset} = DateTime.from_iso8601(str)
    datetime
  end
end
