defmodule HighSociety.Games.TournamentCoordinator do
  @moduledoc """
  One GenServer per *running* tournament, registered under the shared
  `HighSociety.Games.TournamentRegistry` (tagged `{:coordinator, tournament_id}`).
  Owns everything a `HighSociety.Games.TournamentTable` itself can't: initial
  seating, the blind-level/break clock, late registration, assigning
  `finish_place` as players bust, and keeping tables balanced (via the pure
  `HighSociety.Games.TournamentBalancer.rebalance/2`) as the field shrinks.

  Blinds/break state are pushed to every table it owns by **cast**
  (`TournamentTable.set_blinds/4`, `set_on_break/2`) - never a call, which
  would turn this process into a bottleneck across every table's every
  hand. Rebalance moves are **add-then-remove**: the destination seat is
  filled first (`TournamentTable.seat_transfer/5`, synchronous, so it's
  certain to have succeeded before anything else happens), then the source
  seat is only *marked* for removal (`mark_for_removal/2`) - worst case a
  brief cosmetic double-listing, never a player who vanishes because a
  destination seat failed.

  Started only by an admin explicitly starting a tournament
  (`HighSociety.Tournaments.start!/1`) or by
  `HighSociety.Games.TournamentsSupervisor.rehydrate_in_flight_tournaments!/0`
  after a crash/deploy - in the latter case `init/1` finds its tables
  already rehydrated (see that module's boot-ordering note) and simply
  reattaches to them via `handle_continue(:initial_seating, ...)` only
  firing when *no* tables exist yet for this tournament, rather than
  recreating anything.
  """
  use GenServer

  import Ecto.Query

  alias HighSociety.Accounts
  alias HighSociety.Games.PokerTables
  alias HighSociety.Games.TournamentBalancer
  alias HighSociety.Games.TournamentTable
  alias HighSociety.Games.TournamentTableState
  alias HighSociety.Repo
  alias HighSociety.Social
  alias HighSociety.Tournaments.Notifier
  alias HighSociety.Tournaments.PokerTournament
  alias HighSociety.Tournaments.PokerTournamentEntry

  ## Public API

  def start_link(%{tournament_id: tournament_id} = args),
    do: GenServer.start_link(__MODULE__, args, name: via(tournament_id))

  def via(tournament_id),
    do: {:via, Registry, {HighSociety.Games.TournamentRegistry, {:coordinator, tournament_id}}}

  @doc "The PubSub topic a tournament's live progress is broadcast on."
  def topic(tournament_id), do: "tournament:#{tournament_id}"

  @doc "The coordinator's current public state."
  def get_state(tournament_id), do: GenServer.call(via(tournament_id), :get_state)

  @doc """
  Seats `user_id` (with `username`) at whichever active table has room
  (creating a fresh one if every table's full), using the tournament's
  starting stack - only while still inside the tournament's late
  registration window, keyed off `started_at` (not any in-memory elapsed
  time, so a coordinator restart never resets or extends the window).
  """
  def late_join(tournament_id, user_id, username),
    do: GenServer.call(via(tournament_id), {:late_join, user_id, username})

  ## Callbacks

  @impl true
  def init(%{tournament_id: tournament_id}) do
    Process.set_label({:tournament_coordinator, tournament_id})

    tournament = Repo.get!(PokerTournament, tournament_id)
    existing_tables = active_tables(tournament_id)

    state = %{
      tournament_id: tournament_id,
      starting_stack: tournament.starting_stack,
      level_minutes: tournament.level_minutes,
      break_minutes: tournament.break_minutes,
      levels_per_break: max(1, div(tournament.break_every_minutes, tournament.level_minutes)),
      late_registration_minutes: tournament.late_registration_minutes,
      blind_levels: tournament.blind_levels,
      started_at: tournament.started_at,
      current_level: tournament.current_level,
      level_started_at: tournament.level_started_at,
      on_break: tournament.on_break,
      break_ends_at: tournament.break_ends_at,
      tables: Map.new(existing_tables, &{&1.slug, table_occupant_ids(&1)}),
      next_table_number: length(existing_tables),
      timer_ref: nil
    }

    if existing_tables == [] do
      {:ok, state, {:continue, :initial_seating}}
    else
      {:ok, resume_timer(state, tournament)}
    end
  end

  @impl true
  def handle_continue(:initial_seating, state) do
    entries =
      Repo.all(
        from e in PokerTournamentEntry,
          where: e.tournament_id == ^state.tournament_id and is_nil(e.bought_in_at),
          preload: :user
      )

    capacity = PokerTables.seats()
    num_tables = max(1, ceil(length(entries) / capacity))
    slugs = for n <- 1..num_tables, do: table_slug(state.tournament_id, n)
    Enum.each(slugs, &TournamentTable.create!(state.tournament_id, &1))

    tables =
      entries
      |> Enum.with_index()
      |> Enum.reduce(Map.new(slugs, &{&1, []}), fn {entry, i}, tables ->
        slug = Enum.at(slugs, rem(i, num_tables))
        seat_player!(slug, entry, state.starting_stack)
        Map.update!(tables, slug, &[entry.user_id | &1])
      end)

    state = %{state | tables: tables, next_table_number: num_tables}
    broadcast(state)
    {:noreply, schedule_timer(state)}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, public_view(state), state}

  def handle_call({:late_join, user_id, username}, _from, state) do
    elapsed_minutes = DateTime.diff(DateTime.utc_now(), state.started_at, :second) / 60

    if elapsed_minutes > state.late_registration_minutes do
      {:reply, {:error, :late_registration_closed}, state}
    else
      {slug, state} = destination_for_new_player(state)
      move_id = "late-join-#{user_id}"

      case TournamentTable.seat_transfer(slug, move_id, user_id, username, state.starting_stack) do
        {:ok, _view} ->
          record_bought_in!(state.tournament_id, user_id)
          state = update_in(state.tables[slug], &[user_id | &1])
          broadcast(state)
          {:reply, {:ok, slug}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_cast({:eliminations, table_slug, eliminated}, state) do
    remaining_before = total_remaining(state.tables)
    busted_ids = Enum.map(eliminated, & &1.user_id)

    eliminated
    |> Enum.sort_by(& &1.stack_before_hand, :asc)
    |> Enum.with_index()
    |> Enum.each(fn {bust, i} ->
      record_elimination!(state.tournament_id, bust.user_id, remaining_before - i)
    end)

    tables = Map.update(state.tables, table_slug, [], &(&1 -- busted_ids))
    remaining_after = total_remaining(tables)
    state = %{state | tables: tables}

    if remaining_after <= 1 do
      [champion_id] = tables |> Map.values() |> List.flatten()
      record_champion!(state.tournament_id, champion_id)
      state = cancel_timer(state)
      finish_tournament!(state.tournament_id)
      broadcast(state)
      {:noreply, state}
    else
      state = apply_rebalance(state)
      broadcast(state)
      {:noreply, state}
    end
  end

  def handle_cast({:seats_freed, table_slug, _freed}, state) do
    tables =
      case Map.get(state.tables, table_slug) do
        [] -> Map.delete(state.tables, table_slug)
        _ -> state.tables
      end

    {:noreply, %{state | tables: tables}}
  end

  @impl true
  def handle_info(:advance, state) do
    # Once the final level is reached (and no break is pending), no more
    # `:advance` is ever scheduled - this guard makes that explicit/
    # defensive rather than relying solely on nothing sending one, since
    # `advance_level/1` indexing past the last blind level would
    # otherwise crash the process.
    if final_level?(state) and not state.on_break do
      {:noreply, state}
    else
      state =
        cond do
          state.on_break -> end_break_and_advance(state)
          should_break?(state) -> start_break(state)
          true -> advance_level(state)
        end

      broadcast(state)

      if state.on_break or not final_level?(state) do
        {:noreply, schedule_timer(state)}
      else
        {:noreply, %{state | timer_ref: nil}}
      end
    end
  end

  ## Initial seating

  defp table_slug(tournament_id, n), do: "t#{tournament_id}-#{n}"

  defp seat_player!(slug, %PokerTournamentEntry{} = entry, stack) do
    record_bought_in!(entry, DateTime.utc_now(:second))
    username = Accounts.display_name(entry.user)
    move_id = "initial-#{entry.user_id}"
    {:ok, _view} = TournamentTable.seat_transfer(slug, move_id, entry.user_id, username, stack)
    :ok
  end

  defp active_tables(tournament_id) do
    Repo.all(
      from t in TournamentTableState,
        where: t.tournament_id == ^tournament_id and t.status == "active"
    )
  end

  defp table_occupant_ids(%TournamentTableState{seats: seats}) do
    seats |> Enum.reject(&is_nil/1) |> Enum.map(& &1["user_id"])
  end

  ## Late registration

  defp destination_for_new_player(state) do
    capacity = PokerTables.seats()

    candidate =
      state.tables
      |> Enum.filter(fn {_slug, ids} -> length(ids) < capacity end)
      |> Enum.min_by(fn {_slug, ids} -> length(ids) end, fn -> nil end)

    case candidate do
      {slug, _ids} ->
        {slug, state}

      nil ->
        n = state.next_table_number + 1
        slug = table_slug(state.tournament_id, n)
        TournamentTable.create!(state.tournament_id, slug)
        state = %{state | tables: Map.put(state.tables, slug, []), next_table_number: n}
        {slug, state}
    end
  end

  ## Eliminations + rebalancing

  defp total_remaining(tables), do: tables |> Map.values() |> List.flatten() |> length()

  defp apply_rebalance(state) do
    balancer_tables = Enum.map(state.tables, fn {slug, ids} -> %{slug: slug, user_ids: ids} end)
    moves = TournamentBalancer.rebalance(balancer_tables, PokerTables.seats())
    Enum.reduce(moves, state, &apply_move/2)
  end

  defp apply_move(%{user_id: user_id, from: from_slug, to: to_slug}, state) do
    case find_seat_by_user(from_slug, user_id) do
      nil ->
        state

      %{username: username, stack: stack} ->
        move_id = "rebalance-#{user_id}-#{to_slug}-#{state.current_level}"

        case TournamentTable.seat_transfer(to_slug, move_id, user_id, username, stack) do
          {:ok, _view} ->
            TournamentTable.mark_for_removal(from_slug, user_id)

            %{
              state
              | tables:
                  state.tables
                  |> Map.update(from_slug, [], &List.delete(&1, user_id))
                  |> Map.update(to_slug, [user_id], &[user_id | &1])
            }

          {:error, _reason} ->
            state
        end
    end
  end

  defp find_seat_by_user(slug, user_id) do
    slug
    |> TournamentTable.get_state()
    |> Map.fetch!(:seats)
    |> Map.values()
    |> Enum.find(&(&1.user_id == user_id))
  end

  ## Blind levels / breaks

  defp final_level?(state), do: state.current_level >= length(state.blind_levels)

  defp should_break?(state),
    do: not final_level?(state) and rem(state.current_level, state.levels_per_break) == 0

  defp end_break_and_advance(state) do
    state = %{state | on_break: false, break_ends_at: nil}
    push_break(state, false)
    advance_level(state)
  end

  defp start_break(state) do
    ends_at = DateTime.add(DateTime.utc_now(), state.break_minutes * 60, :second)
    state = %{state | on_break: true, break_ends_at: ends_at}
    persist_progress!(state)
    push_break(state, true)
    state
  end

  defp advance_level(state) do
    new_level = state.current_level + 1
    state = %{state | current_level: new_level, level_started_at: DateTime.utc_now(:second)}
    persist_progress!(state)
    push_blinds(state)
    state
  end

  defp blind_at(state, level) do
    %{"small_blind" => sb, "big_blind" => bb} = Enum.at(state.blind_levels, level - 1)
    {sb, bb}
  end

  defp push_blinds(state) do
    {sb, bb} = blind_at(state, state.current_level)

    Enum.each(
      Map.keys(state.tables),
      &TournamentTable.set_blinds(&1, sb, bb, state.current_level)
    )
  end

  defp push_break(state, on_break?),
    do: Enum.each(Map.keys(state.tables), &TournamentTable.set_on_break(&1, on_break?))

  defp schedule_timer(state) do
    ms = if state.on_break, do: state.break_minutes * 60_000, else: state.level_minutes * 60_000
    ref = Process.send_after(self(), :advance, ms)
    %{state | timer_ref: ref}
  end

  defp resume_timer(state, tournament) do
    if final_level?(state) and not state.on_break do
      %{state | timer_ref: nil}
    else
      remaining_ms =
        if state.on_break do
          DateTime.diff(tournament.break_ends_at, DateTime.utc_now(), :millisecond)
        else
          elapsed = DateTime.diff(DateTime.utc_now(), tournament.level_started_at, :millisecond)
          state.level_minutes * 60_000 - elapsed
        end
        |> max(0)

      ref = Process.send_after(self(), :advance, remaining_ms)
      %{state | timer_ref: ref}
    end
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end

  ## Persistence

  defp persist_progress!(state) do
    Repo.update_all(
      from(t in PokerTournament, where: t.id == ^state.tournament_id),
      set: [
        current_level: state.current_level,
        level_started_at: state.level_started_at,
        on_break: state.on_break,
        break_ends_at: state.break_ends_at
      ]
    )

    :ok
  end

  defp record_bought_in!(%PokerTournamentEntry{} = entry, now) do
    entry |> PokerTournamentEntry.placement_changeset(%{bought_in_at: now}) |> Repo.update!()
  end

  defp record_bought_in!(tournament_id, user_id) do
    now = DateTime.utc_now(:second)
    entry = Repo.get_by!(PokerTournamentEntry, tournament_id: tournament_id, user_id: user_id)
    record_bought_in!(entry, now)
  end

  defp record_elimination!(tournament_id, user_id, place) do
    now = DateTime.utc_now(:second)
    entry = Repo.get_by!(PokerTournamentEntry, tournament_id: tournament_id, user_id: user_id)

    entry
    |> PokerTournamentEntry.placement_changeset(%{finish_place: place, eliminated_at: now})
    |> Repo.update!()
  end

  defp record_champion!(tournament_id, user_id) do
    entry = Repo.get_by!(PokerTournamentEntry, tournament_id: tournament_id, user_id: user_id)
    entry |> PokerTournamentEntry.placement_changeset(%{finish_place: 1}) |> Repo.update!()
  end

  # Marks the tournament finished and emails every entrant their result.
  # Off a detached process (same non-blocking-handler reason
  # `PokerTable.finalize/2` runs `PokerBots.maintain!/0` off a `Task`) so
  # this `handle_cast` isn't blocked for however long a full batch send
  # takes - deliberately a bare `spawn/1`, not `Task.start/1`: `Task`
  # propagates `$callers`, and Swoosh's test mail adapter broadcasts each
  # delivered email to every pid in that chain - which would otherwise
  # include this coordinator itself, crashing it on the unhandled
  # `{:email, ...}` message it has no `handle_info` clause for.
  defp finish_tournament!(tournament_id) do
    now = DateTime.utc_now(:second)

    Repo.update_all(
      from(t in PokerTournament, where: t.id == ^tournament_id),
      set: [status: "finished", finished_at: now]
    )

    tournament = Repo.get!(PokerTournament, tournament_id)

    entries =
      PokerTournamentEntry
      |> where([e], e.tournament_id == ^tournament_id)
      |> preload(:user)
      |> Repo.all()

    spawn(fn -> Notifier.deliver_results(tournament, entries) end)

    # Off the hot path for the same reason as the notifier above - with
    # auto-post enabled this makes a live HTTP call to X, which must never
    # block this coordinator.
    if champion = Enum.find(entries, &(&1.finish_place == 1)) do
      spawn(fn -> Social.draft_tournament_win_post!(tournament, champion.user) end)
    end

    :ok
  end

  ## Broadcast

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(
      HighSociety.PubSub,
      topic(state.tournament_id),
      {:tournament_updated, public_view(state)}
    )
  end

  defp public_view(state) do
    {sb, bb} = blind_at(state, state.current_level)

    %{
      tournament_id: state.tournament_id,
      current_level: state.current_level,
      small_blind: sb,
      big_blind: bb,
      on_break: state.on_break,
      break_ends_at: state.break_ends_at,
      remaining: total_remaining(state.tables),
      tables: state.tables
    }
  end
end
