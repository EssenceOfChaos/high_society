defmodule HighSociety.Games.PokerTable do
  @moduledoc """
  One GenServer per Poker table (see `HighSociety.Games.PokerTables`),
  registered under `HighSociety.Games.PokerRegistry` by slug. This is the
  single authoritative process for a table: every seat/stand/action call
  is serialized through it, so concurrent players acting at once can never
  race each other the way two LiveViews independently writing to Postgres
  could.

  Durable state (who's seated where, with how many chips, and whose
  button it is) and the in-progress hand (if any) are both persisted to a
  `HighSociety.Games.PokerTableState` row after every change, so a deploy
  or crash never loses seated players' chips - `init/1` reloads that row
  and, if a hand was mid-action past its deadline when the process died,
  immediately resolves that timeout before anything else happens.
  """
  use GenServer

  alias HighSociety.Accounts
  alias HighSociety.Games.Poker
  alias HighSociety.Games.PokerBots
  alias HighSociety.Games.PokerTables
  alias HighSociety.Games.PokerTableState
  alias HighSociety.Repo

  @action_seconds 20
  @hand_over_pause_ms 4_000

  ## Public API

  def start_link(table_config),
    do: GenServer.start_link(__MODULE__, table_config, name: via(table_config.slug))

  def via(slug), do: {:via, Registry, {HighSociety.Games.PokerRegistry, slug}}

  @doc "The PubSub topic a table's updates are broadcast on."
  def topic(slug), do: "poker_table:#{slug}"

  @doc "How long (seconds) a player has to act before their turn is forfeited."
  def action_seconds, do: @action_seconds

  @doc "Seats `user` at `seat_index` for `buy_in` chips, debiting their balance."
  def sit(slug, user, seat_index, buy_in),
    do: GenServer.call(via(slug), {:sit, user, seat_index, buy_in})

  @doc "Stands `user_id` up, cashing their current stack back to their balance."
  def stand(slug, user_id), do: GenServer.call(via(slug), {:stand, user_id})

  @doc "Takes `action` (`:check`, `:fold`, `:call`, `:bet`, `:raise`) for `user_id`'s seat."
  def act(slug, user_id, action, amount \\ nil),
    do: GenServer.call(via(slug), {:act, user_id, action, amount})

  @doc "The table's current public state."
  def get_state(slug), do: GenServer.call(via(slug), :get_state)

  ## Callbacks

  @impl true
  def init(table_config) do
    # `init/1` runs at application boot, which can be earlier than
    # anything else has caused `Poker` to actually be loaded (Elixir
    # loads modules lazily outside a compiled release) - and it's that
    # loading, not merely compiling, which interns a module's literal
    # atoms (`:preflop`, `:folded`, etc). Without this, deserializing a
    # persisted hand via `String.to_existing_atom/1` below can raise on
    # a genuine restart, exactly when recovering an in-progress hand
    # matters most.
    Code.ensure_loaded!(Poker)
    state = table_config |> load_or_create() |> catch_up()
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, public_view(state), state}

  def handle_call({:sit, user, seat_index, buy_in}, _from, state) do
    table = state.config

    cond do
      seat_index not in 0..(PokerTables.seats() - 1) ->
        {:reply, {:error, :invalid_seat}, state}

      Map.has_key?(state.seats, seat_index) ->
        {:reply, {:error, :seat_taken}, state}

      Enum.any?(state.seats, fn {_i, s} -> s.user_id == user.id end) ->
        {:reply, {:error, :already_seated}, state}

      buy_in < PokerTables.min_buy_in(table) or buy_in > PokerTables.max_buy_in(table) ->
        {:reply, {:error, :invalid_buy_in}, state}

      true ->
        case Accounts.adjust_balance(user, -buy_in) do
          {:ok, _user} ->
            entry = %{user_id: user.id, username: username(user), stack: buy_in}

            state =
              %{state | seats: Map.put(state.seats, seat_index, entry)}
              |> maybe_start_hand()
              |> finalize()

            {:reply, {:ok, public_view(state)}, state}

          {:error, :insufficient_funds} ->
            {:reply, {:error, :insufficient_funds}, state}
        end
    end
  end

  def handle_call({:stand, user_id}, _from, state) do
    case find_seat(state, user_id) do
      nil ->
        {:reply, {:error, :not_seated}, state}

      seat_index ->
        {cash_out, state} = leave_seat(state, seat_index)
        {:ok, _user} = Accounts.adjust_balance(Accounts.get_user!(user_id), cash_out)
        state = state |> maybe_start_hand() |> finalize()
        {:reply, {:ok, public_view(state)}, state}
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
                state = state |> apply_hand_result(new_hand) |> finalize(last_action)
                {:reply, {:ok, public_view(state)}, state}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end
        end
    end
  end

  @impl true
  def handle_info({:action_timeout, seat_index, hand_ref}, state) do
    if (hand_ref == state.hand_ref and state.hand) && state.hand.action_on == seat_index do
      # Mirrors `Poker.timeout/2`'s own check-vs-fold choice, computed
      # ahead of time so the forfeited action can be named in the
      # broadcast for `:last_action` (used client-side to pick a sound).
      seat = Map.fetch!(state.hand.seats, seat_index)
      action = if seat.contributed_this_street == state.hand.current_bet, do: :check, else: :fold

      new_hand = Poker.timeout(state.hand, seat_index)
      last_action = %{seat: seat_index, action: action, all_in: false}
      {:noreply, state |> apply_hand_result(new_hand) |> finalize(last_action)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:start_next_hand, hand_ref}, state) do
    if hand_ref == state.hand_ref do
      {:noreply, state |> maybe_start_hand_after_pause() |> finalize()}
    else
      {:noreply, state}
    end
  end

  # See `HighSociety.Games.PokerBots` - only ever scheduled (in
  # `maybe_schedule_bot/1`) when a dev bot is actually on the clock, and
  # only in dev, so this clause is simply never reached elsewhere.
  def handle_info({:bot_act, seat_index, hand_ref}, state) do
    if (hand_ref == state.hand_ref and state.hand) && state.hand.action_on == seat_index do
      seat = Map.fetch!(state.hand.seats, seat_index)
      can_check? = seat.contributed_this_street == state.hand.current_bet
      action = PokerBots.choose_action(can_check?)

      case dispatch_action(state.hand, seat_index, action, nil) do
        {:ok, new_hand} ->
          last_action = last_action(seat_index, action, new_hand)
          {:noreply, state |> apply_hand_result(new_hand) |> finalize(last_action)}

        {:error, _reason} ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  ## Sitting / standing

  defp maybe_start_hand(%{hand: nil, seats: seats} = state) when map_size(seats) >= 2,
    do: start_new_hand(state)

  defp maybe_start_hand(state), do: state

  defp maybe_start_hand_after_pause(%{seats: seats} = state) when map_size(seats) >= 2,
    do: start_new_hand(state)

  defp maybe_start_hand_after_pause(state), do: %{state | hand: nil}

  defp start_new_hand(state) do
    occupied = state.seats |> Map.keys() |> Enum.sort()
    button_seat = next_button_seat(state.button_seat, occupied)

    hand =
      Poker.start_hand(state.seats, button_seat, state.config.small_blind, state.config.big_blind)

    state = %{state | button_seat: button_seat, hand_ref: state.hand_ref + 1}
    apply_hand_result(state, hand)
  end

  defp next_button_seat(nil, occupied), do: hd(occupied)

  defp next_button_seat(previous, occupied),
    do: Enum.find(occupied, &(&1 > previous)) || hd(occupied)

  # Removes a seat from the table. If it's currently part of the hand in
  # progress, folds it in place (regardless of whose turn it is) and cashes
  # out whatever stack remains after that fold; otherwise (no hand, or the
  # seat sat down too late to be dealt into this one) simply cashes out its
  # durable stack as-is. Only reschedules the action timer when leaving
  # actually changed who's on the clock (it was this seat's own turn, or
  # the hand just ended) - if someone else was already deciding, their
  # countdown keeps running untouched.
  defp leave_seat(%{hand: %Poker{seats: hand_seats} = hand} = state, seat_index)
       when is_map_key(hand_seats, seat_index) do
    previous_action_on = hand.action_on
    new_hand = Poker.force_fold(hand, seat_index)
    cash_out = new_hand.seats[seat_index].stack
    new_hand = put_in(new_hand.seats[seat_index].stack, 0)
    state = %{state | seats: Map.delete(state.seats, seat_index)}

    state =
      if new_hand.status == :hand_over or new_hand.action_on != previous_action_on do
        apply_hand_result(state, new_hand)
      else
        %{state | hand: new_hand}
      end

    {cash_out, state}
  end

  defp leave_seat(state, seat_index) do
    cash_out = Map.fetch!(state.seats, seat_index).stack
    {cash_out, %{state | seats: Map.delete(state.seats, seat_index)}}
  end

  defp find_seat(state, user_id) do
    case Enum.find(state.seats, fn {_i, s} -> s.user_id == user_id end) do
      nil -> nil
      {seat_index, _seat} -> seat_index
    end
  end

  defp username(user), do: user.email |> String.split("@") |> hd()

  ## Actions

  defp dispatch_action(hand, seat, :check, _amount), do: Poker.check(hand, seat)
  defp dispatch_action(hand, seat, :fold, _amount), do: Poker.fold(hand, seat)
  defp dispatch_action(hand, seat, :call, _amount), do: Poker.call(hand, seat)
  defp dispatch_action(hand, seat, :bet, amount), do: Poker.bet(hand, seat, amount)
  defp dispatch_action(hand, seat, :raise, amount), do: Poker.raise(hand, seat, amount)

  # Names the action just taken for the broadcast's `:last_action`, so
  # every connected client (not just the actor) can play the matching
  # sound - flagged `all_in: true` when a wager left the seat with
  # nothing left, regardless of which of the three wagering actions got
  # it there.
  defp last_action(seat, action, new_hand) when action in [:call, :bet, :raise],
    do: %{seat: seat, action: action, all_in: match?(%{stack: 0}, new_hand.seats[seat])}

  defp last_action(seat, action, _new_hand), do: %{seat: seat, action: action, all_in: false}

  # Applies the result of any hand-mutating action (a player's action, a
  # timeout forfeit, or a fresh deal): cancels whatever timer was running,
  # then either merges every seat's stack back into the durable seat map
  # and schedules the next hand's brief pause (auto-standing anyone left
  # with $0), or schedules a fresh action-clock timeout for whoever's now
  # on the action.
  defp apply_hand_result(state, new_hand) do
    state = cancel_timer(state)

    if new_hand.status == :hand_over do
      seats = merge_hand_stacks(state.seats, new_hand)

      timer_ref =
        Process.send_after(self(), {:start_next_hand, state.hand_ref}, @hand_over_pause_ms)

      %{state | seats: seats, hand: new_hand, action_deadline: nil, timer_ref: timer_ref}
    else
      deadline = DateTime.add(DateTime.utc_now(), @action_seconds, :second)

      timer_ref =
        Process.send_after(
          self(),
          {:action_timeout, new_hand.action_on, state.hand_ref},
          @action_seconds * 1000
        )

      state = %{state | hand: new_hand, action_deadline: deadline, timer_ref: timer_ref}
      maybe_schedule_bot(state)
    end
  end

  # See `HighSociety.Games.PokerBots` - a no-op whenever it's disabled
  # (everywhere but dev) or the seat now on the action isn't a bot's.
  defp maybe_schedule_bot(state) do
    seat = Map.get(state.hand.seats, state.hand.action_on)

    if seat && PokerBots.bot?(seat.user_id) do
      Process.send_after(
        self(),
        {:bot_act, state.hand.action_on, state.hand_ref},
        PokerBots.think_time_ms()
      )
    end

    state
  end

  defp merge_hand_stacks(durable_seats, %Poker{seats: hand_seats}) do
    Enum.reduce(hand_seats, durable_seats, fn {i, hand_seat}, acc ->
      case Map.get(acc, i) do
        nil ->
          acc

        durable_seat ->
          if hand_seat.stack <= 0,
            do: Map.delete(acc, i),
            else: Map.put(acc, i, %{durable_seat | stack: hand_seat.stack})
      end
    end)
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end

  ## Crash recovery

  # These tables are started once, as part of the OTP supervision tree, at
  # application boot - including in the test environment, well before any
  # individual test has checked out (or shared) an Ecto Sandbox connection.
  # A boot-time `Repo` call under the test config's `:manual` sandbox mode
  # would raise `DBConnection.OwnershipError` for exactly that reason (no
  # test has claimed a connection yet), which would otherwise crash this
  # process - and, since it's `:permanent`, crash-loop the whole
  # supervision tree. Falling back to a fresh, unpersisted table in that
  # one narrow case is safe: it only ever happens before a single request
  # has touched this table, and every real call after that point runs
  # inside a test that's already claimed a connection (or, outside tests,
  # a real database that's simply present at boot).
  defp load_or_create(table_config) do
    case load_row(table_config.slug) do
      {:ok, row} -> from_row(table_config, row)
      :unavailable -> fresh_state(table_config)
    end
  end

  defp load_row(slug) do
    row =
      Repo.get_by(PokerTableState, slug: slug) ||
        Repo.insert!(%PokerTableState{
          slug: slug,
          seats: List.duplicate(nil, PokerTables.seats()),
          button_seat: nil,
          hand: nil
        })

    {:ok, row}
  rescue
    # `OwnershipError` is the boot-time case described above. `ConnectionError`
    # covers the same family of test-only race from the other side: a table
    # reset mid-suite (see `HighSociety.PokerFixtures.reset_table!/1`) can
    # have this fresh process reach its own `init/1` a moment before the test
    # that triggered the reset has torn down its sandbox connection - so the
    # query starts against a connection that gets pulled out from under it.
    # Both are safe to treat the same way: start fresh, exactly as if no row
    # existed yet.
    _e in [DBConnection.OwnershipError, DBConnection.ConnectionError] -> :unavailable
  end

  defp from_row(table_config, row) do
    wrapper = row.hand

    %{
      slug: table_config.slug,
      config: table_config,
      seats: seats_row_from_json(row.seats),
      button_seat: row.button_seat,
      hand: wrapper && hand_from_json(wrapper["poker"]),
      hand_ref: (wrapper && wrapper["hand_ref"]) || 0,
      action_deadline:
        wrapper && wrapper["action_deadline"] && parse_iso8601(wrapper["action_deadline"]),
      timer_ref: nil
    }
  end

  defp fresh_state(table_config) do
    %{
      slug: table_config.slug,
      config: table_config,
      seats: %{},
      button_seat: nil,
      hand: nil,
      hand_ref: 0,
      action_deadline: nil,
      timer_ref: nil
    }
  end

  defp catch_up(%{hand: nil} = state), do: state

  defp catch_up(%{hand: %{status: :hand_over}} = state) do
    state = maybe_start_hand_after_pause(state)
    persist(state)
    state
  end

  # An in-progress hand with nobody left to act (a full all-in run-out)
  # always resolves synchronously inside `Poker`, so a persisted hand
  # never has `action_on: nil` while still `:in_progress` - but if it
  # somehow did, there's nothing to catch up on: it's just waiting for the
  # next street's cards, which only ever happens as part of an action this
  # process already took.
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

  ## Persistence + broadcast

  defp finalize(state, last_action \\ nil) do
    persist(state)
    broadcast(state, last_action)
    # Off a separate process: `PokerBots.maintain!/0` calls back into
    # `sit/4` on this same table, which would deadlock if run inline here.
    # `enabled?/0` keeps this a no-op everywhere but dev.
    if PokerBots.enabled?(), do: Task.start(&PokerBots.maintain!/0)
    state
  end

  defp persist(state) do
    now = DateTime.utc_now(:second)

    %PokerTableState{}
    |> PokerTableState.changeset(%{
      slug: state.slug,
      seats: seats_row_to_json(state.seats),
      button_seat: state.button_seat,
      hand: hand_wrapper_to_json(state)
    })
    |> Ecto.Changeset.put_change(:inserted_at, now)
    |> Ecto.Changeset.put_change(:updated_at, now)
    |> Repo.insert!(
      on_conflict: {:replace, [:seats, :button_seat, :hand, :updated_at]},
      conflict_target: :slug
    )
  end

  defp broadcast(state, last_action) do
    Phoenix.PubSub.broadcast(
      HighSociety.PubSub,
      topic(state.slug),
      {:poker_table_updated, public_view(state, last_action)}
    )
  end

  defp public_view(state, last_action \\ nil) do
    %{
      slug: state.slug,
      config: state.config,
      seats: state.seats,
      button_seat: state.button_seat,
      hand: state.hand,
      action_deadline: state.action_deadline,
      last_action: last_action
    }
  end

  ## JSON (de)serialization - the persisted row stores plain jsonb, so
  ## atoms/tuples/integer-keyed maps need converting at the boundary; this
  ## mirrors `HighSociety.Games` doing the same for Blackjack and War.

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
          Map.new(poker.uncalled_return, fn {k, v} -> {Atom.to_string(k), v} end)
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
          %{seat: h["uncalled_return"]["seat"], amount: h["uncalled_return"]["amount"]}
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
