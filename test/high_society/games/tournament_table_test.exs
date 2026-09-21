defmodule HighSociety.Games.TournamentTableTest do
  use HighSociety.DataCase, async: false

  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures

  alias HighSociety.Games.TournamentTable
  alias HighSociety.Games.TournamentTableState

  setup do
    tournament = tournament_fixture()
    %{tournament: tournament}
  end

  # `TournamentTable` casts eliminations/freed-seats to whatever's
  # registered under `{:coordinator, tournament_id}` in the shared
  # registry - registering the test process itself there lets these tests
  # assert on that wiring without a real `TournamentCoordinator` (phase 3)
  # existing yet. `GenServer.cast/2` on a `:via` name just delivers a raw
  # `{:"$gen_cast", msg}` to whatever's registered, so a plain process
  # (not a GenServer) can still receive and assert on it.
  defp register_as_coordinator!(tournament_id) do
    {:ok, _owner} =
      Registry.register(HighSociety.Games.TournamentRegistry, {:coordinator, tournament_id}, nil)

    :ok
  end

  describe "create!/2" do
    test "starts empty and active", %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)
      view = TournamentTable.get_state(slug)

      assert view.slug == slug
      assert view.seats == %{}
      assert view.hand == nil
      assert Repo.get_by(TournamentTableState, slug: slug).status == "active"
    end

    test "reads its blinds from the tournament's current level", %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)
      view = TournamentTable.get_state(slug)

      assert view.small_blind == 100
      assert view.big_blind == 200
      assert view.level == 1
      assert view.on_break == false
    end
  end

  describe "seat_transfer/5" do
    test "seats a user at the first open seat, dealing a hand once 2+ are seated", %{
      tournament: tournament
    } do
      slug = tournament_table_fixture!(tournament)
      user_a = user_fixture()

      assert {:ok, view} = TournamentTable.seat_transfer(slug, "move-1", user_a.id, "A", 10_000)
      assert view.seats[0].user_id == user_a.id
      assert view.hand == nil

      user_b = user_fixture()
      assert {:ok, view} = TournamentTable.seat_transfer(slug, "move-2", user_b.id, "B", 10_000)
      assert view.seats[1].user_id == user_b.id
      assert view.hand != nil
    end

    test "is idempotent by move_id - a retried call doesn't double-seat", %{
      tournament: tournament
    } do
      slug = tournament_table_fixture!(tournament)
      user_a = user_fixture()

      assert {:ok, _view} = TournamentTable.seat_transfer(slug, "move-1", user_a.id, "A", 10_000)
      assert {:ok, view} = TournamentTable.seat_transfer(slug, "move-1", user_a.id, "A", 10_000)

      assert map_size(view.seats) == 1
    end

    test "rejects seating once every seat is taken", %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)

      for i <- 1..8 do
        user = user_fixture()

        assert {:ok, _view} =
                 TournamentTable.seat_transfer(slug, "move-#{i}", user.id, "P#{i}", 10_000)
      end

      overflow_user = user_fixture()

      assert {:error, :table_full} =
               TournamentTable.seat_transfer(slug, "move-9", overflow_user.id, "P9", 10_000)
    end

    test "does not deal while the tournament is on break", %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)
      TournamentTable.set_on_break(slug, true)

      user_a = user_fixture()
      user_b = user_fixture()
      TournamentTable.seat_transfer(slug, "move-1", user_a.id, "A", 10_000)
      {:ok, view} = TournamentTable.seat_transfer(slug, "move-2", user_b.id, "B", 10_000)

      assert view.hand == nil
    end
  end

  describe "set_blinds/4 and set_on_break/2" do
    test "pushes new blinds, applied to the next hand", %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)
      Phoenix.PubSub.subscribe(HighSociety.PubSub, TournamentTable.topic(slug))

      TournamentTable.set_blinds(slug, 700, 1_400, 6)
      assert_receive {:tournament_table_updated, view}
      assert view.small_blind == 700
      assert view.big_blind == 1_400
      assert view.level == 6

      user_a = user_fixture()
      user_b = user_fixture()
      TournamentTable.seat_transfer(slug, "move-1", user_a.id, "A", 10_000)
      {:ok, view} = TournamentTable.seat_transfer(slug, "move-2", user_b.id, "B", 10_000)

      assert view.hand.small_blind == 700
      assert view.hand.big_blind == 1_400
    end
  end

  describe "act/4 and eliminations" do
    test "a heads-up all-in either eliminates the loser or (rarely) chops - notification always matches reality",
         %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)
      register_as_coordinator!(tournament.id)

      button_user = user_fixture()
      other_user = user_fixture()
      TournamentTable.seat_transfer(slug, "move-1", button_user.id, "Button", 1_000)
      {:ok, _view} = TournamentTable.seat_transfer(slug, "move-2", other_user.id, "Other", 1_000)

      assert {:ok, _view} = TournamentTable.act(slug, button_user.id, :raise, 1_000)
      assert {:ok, view} = TournamentTable.act(slug, other_user.id, :call)

      remaining_ids = view.seats |> Map.values() |> Enum.map(& &1.user_id) |> MapSet.new()

      case MapSet.to_list(
             MapSet.difference(MapSet.new([button_user.id, other_user.id]), remaining_ids)
           ) do
        [] ->
          # A chop - both kept their original stack, nobody busted.
          refute_receive {:"$gen_cast", {:eliminations, ^slug, _}}

        [busted_id] ->
          assert_receive {:"$gen_cast", {:eliminations, ^slug, [eliminated]}}
          assert eliminated.user_id == busted_id
          assert eliminated.stack_before_hand == 1_000
      end
    end

    test "returns errors for an unseated user or no hand in progress", %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)
      user = user_fixture()

      assert {:error, :not_seated} = TournamentTable.act(slug, user.id, :check)

      TournamentTable.seat_transfer(slug, "move-1", user.id, "Solo", 10_000)
      assert {:error, :no_hand_in_progress} = TournamentTable.act(slug, user.id, :check)
    end
  end

  describe "reveal_hand/2" do
    test "the winner can reveal their hand after an uncontested fold", %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)
      user_a = user_fixture()
      user_b = user_fixture()
      TournamentTable.seat_transfer(slug, "move-1", user_a.id, "A", 10_000)
      {:ok, view} = TournamentTable.seat_transfer(slug, "move-2", user_b.id, "B", 10_000)

      folding_user = if view.hand.action_on == 0, do: user_a, else: user_b
      winning_user = if folding_user == user_a, do: user_b, else: user_a

      {:ok, view} = TournamentTable.act(slug, folding_user.id, :fold)
      assert view.hand.revealed_seats == []

      assert {:ok, view} = TournamentTable.reveal_hand(slug, winning_user.id)
      assert view.hand.revealed_seats != []
    end

    test "the loser can't reveal on the winner's behalf", %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)
      user_a = user_fixture()
      user_b = user_fixture()
      TournamentTable.seat_transfer(slug, "move-1", user_a.id, "A", 10_000)
      {:ok, view} = TournamentTable.seat_transfer(slug, "move-2", user_b.id, "B", 10_000)

      folding_user = if view.hand.action_on == 0, do: user_a, else: user_b
      {:ok, _view} = TournamentTable.act(slug, folding_user.id, :fold)

      assert {:error, :not_a_winner} = TournamentTable.reveal_hand(slug, folding_user.id)
    end

    test "returns an error for a user who isn't seated", %{tournament: tournament} do
      slug = tournament_table_fixture!(tournament)
      user = user_fixture()

      assert {:error, :not_seated} = TournamentTable.reveal_hand(slug, user.id)
    end
  end

  describe "mark_for_removal/2" do
    test "frees marked seats at the next hand-over and closes the table once empty", %{
      tournament: tournament
    } do
      slug = tournament_table_fixture!(tournament)
      register_as_coordinator!(tournament.id)

      user_a = user_fixture()
      user_b = user_fixture()
      TournamentTable.seat_transfer(slug, "move-1", user_a.id, "A", 10_000)
      {:ok, view} = TournamentTable.seat_transfer(slug, "move-2", user_b.id, "B", 10_000)
      assert view.hand != nil

      TournamentTable.mark_for_removal(slug, user_a.id)
      TournamentTable.mark_for_removal(slug, user_b.id)

      acting_user_id = if view.hand.action_on == 0, do: user_a.id, else: user_b.id
      ref = Process.monitor(GenServer.whereis(TournamentTable.via(slug)))

      assert {:ok, _view} = TournamentTable.act(slug, acting_user_id, :fold)

      assert_receive {:"$gen_cast", {:seats_freed, ^slug, freed}}
      freed_ids = Enum.map(freed, & &1.user_id) |> MapSet.new()
      assert freed_ids == MapSet.new([user_a.id, user_b.id])
      refute_receive {:"$gen_cast", {:eliminations, ^slug, _}}

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
      assert Repo.get_by(TournamentTableState, slug: slug).status == "closed"
    end
  end

  describe "crash recovery" do
    test "a killed table restarts with the same seats and current blinds", %{
      tournament: tournament
    } do
      slug = tournament_table_fixture!(tournament)
      user_a = user_fixture()
      user_b = user_fixture()
      TournamentTable.seat_transfer(slug, "move-1", user_a.id, "A", 10_000)
      TournamentTable.seat_transfer(slug, "move-2", user_b.id, "B", 10_000)

      pid = GenServer.whereis(TournamentTable.via(slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      view = wait_for_restart(slug)
      assert map_size(view.seats) == 2
      assert view.small_blind == 100
      assert view.big_blind == 200
    end
  end

  defp wait_for_restart(slug) do
    case GenServer.whereis(TournamentTable.via(slug)) do
      nil ->
        Process.sleep(5)
        wait_for_restart(slug)

      _pid ->
        TournamentTable.get_state(slug)
    end
  end
end
