defmodule HighSociety.Games.TournamentCoordinatorTest do
  use HighSociety.DataCase, async: false

  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures

  alias HighSociety.Games.TournamentCoordinator
  alias HighSociety.Games.TournamentTable
  alias HighSociety.Tournaments

  describe "initial seating" do
    test "seats every pre-registered entrant across enough tables, round-robin" do
      tournament = tournament_fixture()
      users = for _ <- 1..10, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)

      view = TournamentCoordinator.get_state(tournament.id)
      assert view.remaining == 10
      assert map_size(view.tables) == 2

      counts = view.tables |> Map.values() |> Enum.map(&length/1) |> Enum.sort()
      assert counts == [5, 5]

      for user <- users do
        entry =
          Repo.get_by!(Tournaments.PokerTournamentEntry,
            tournament_id: tournament.id,
            user_id: user.id
          )

        assert entry.bought_in_at != nil
      end
    end

    test "a single table for a small field" do
      tournament = tournament_fixture()
      users = for _ <- 1..3, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)

      view = TournamentCoordinator.get_state(tournament.id)
      assert map_size(view.tables) == 1
      assert view.remaining == 3
    end

    test "starts with the tournament's first blind level" do
      tournament = tournament_fixture()
      users = for _ <- 1..3, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)

      view = TournamentCoordinator.get_state(tournament.id)
      assert view.current_level == 1
      assert view.small_blind == 100
      assert view.big_blind == 200
    end
  end

  describe "late_join/3" do
    test "seats a late entrant within the late-registration window" do
      tournament = tournament_fixture()
      users = for _ <- 1..3, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)

      late_user = user_fixture()

      {:ok, _entry} =
        Tournaments.register(HighSociety.Accounts.Scope.for_user(late_user), tournament, %{})

      assert {:ok, slug} = TournamentCoordinator.late_join(tournament.id, late_user.id, "Late")

      view = TournamentTable.get_state(slug)
      assert Enum.any?(view.seats, fn {_i, s} -> s.user_id == late_user.id end)

      entry =
        Repo.get_by!(Tournaments.PokerTournamentEntry,
          tournament_id: tournament.id,
          user_id: late_user.id
        )

      assert entry.bought_in_at != nil
    end

    test "rejects a late entrant once the window has closed" do
      tournament = tournament_fixture()
      users = for _ <- 1..3, do: user_fixture()
      long_ago = DateTime.add(DateTime.utc_now(:second), -3600 * 3, :second)
      tournament = start_tournament_for_test!(tournament, users, started_at: long_ago)

      late_user = user_fixture()

      assert {:error, :late_registration_closed} =
               TournamentCoordinator.late_join(tournament.id, late_user.id, "Late")
    end
  end

  describe "eliminations" do
    test "tie-breaks a same-hand multi-bust by pre-hand stack, worst stack finishes worse" do
      tournament = tournament_fixture()
      users = for _ <- 1..4, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)
      [survivor, big_stack_buster, small_stack_buster, _fourth] = users

      view = TournamentCoordinator.get_state(tournament.id)
      [slug] = Map.keys(view.tables)

      eliminated = [
        %{user_id: big_stack_buster.id, username: "B", stack_before_hand: 5_000},
        %{user_id: small_stack_buster.id, username: "S", stack_before_hand: 1_000}
      ]

      GenServer.cast(TournamentCoordinator.via(tournament.id), {:eliminations, slug, eliminated})
      wait_for_sync(tournament.id)

      small_entry =
        Repo.get_by!(Tournaments.PokerTournamentEntry,
          tournament_id: tournament.id,
          user_id: small_stack_buster.id
        )

      big_entry =
        Repo.get_by!(Tournaments.PokerTournamentEntry,
          tournament_id: tournament.id,
          user_id: big_stack_buster.id
        )

      # 4 remaining before this batch: the two busters take 4th (worse,
      # smaller pre-hand stack) and 3rd (better, bigger pre-hand stack).
      assert small_entry.finish_place == 4
      assert big_entry.finish_place == 3
      assert small_entry.eliminated_at != nil

      survivor_entry =
        Repo.get_by!(Tournaments.PokerTournamentEntry,
          tournament_id: tournament.id,
          user_id: survivor.id
        )

      assert survivor_entry.finish_place == nil

      view = TournamentCoordinator.get_state(tournament.id)
      assert view.remaining == 2
    end

    test "crowns the last remaining player and marks the tournament finished" do
      tournament = tournament_fixture()
      users = for _ <- 1..2, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)
      [champion, runner_up] = users

      view = TournamentCoordinator.get_state(tournament.id)
      [slug] = Map.keys(view.tables)

      eliminated = [%{user_id: runner_up.id, username: "R", stack_before_hand: 10_000}]
      GenServer.cast(TournamentCoordinator.via(tournament.id), {:eliminations, slug, eliminated})
      wait_for_sync(tournament.id)

      champion_entry =
        Repo.get_by!(Tournaments.PokerTournamentEntry,
          tournament_id: tournament.id,
          user_id: champion.id
        )

      assert champion_entry.finish_place == 1
      assert champion_entry.eliminated_at == nil

      reloaded = Repo.get!(Tournaments.PokerTournament, tournament.id)
      assert reloaded.status == "finished"
      assert reloaded.finished_at != nil
    end

    test "consolidates onto one table once the remaining field fits" do
      tournament = tournament_fixture()
      users = for _ <- 1..10, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)

      view = TournamentCoordinator.get_state(tournament.id)
      [slug_a, _slug_b] = Map.keys(view.tables) |> Enum.sort()
      table_a_users = view.tables[slug_a]

      # Bust 3 of table A's 5 players in one batch, leaving 7 total - which
      # fits comfortably on one 8-seat table, so the balancer's rule 1
      # (consolidate) applies rather than just evening the gap out.
      eliminated =
        table_a_users
        |> Enum.take(3)
        |> Enum.map(&%{user_id: &1, username: "P#{&1}", stack_before_hand: 1_000})

      GenServer.cast(
        TournamentCoordinator.via(tournament.id),
        {:eliminations, slug_a, eliminated}
      )

      wait_for_sync(tournament.id)

      view = TournamentCoordinator.get_state(tournament.id)
      assert view.remaining == 7

      counts = view.tables |> Map.values() |> Enum.map(&length/1) |> Enum.sort()
      assert counts == [0, 7]
    end

    test "evens out (without consolidating) when the remaining field doesn't fit on one table" do
      tournament = tournament_fixture()
      users = for _ <- 1..17, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)

      view = TournamentCoordinator.get_state(tournament.id)
      assert map_size(view.tables) == 3

      {target_slug, target_users} = Enum.max_by(view.tables, fn {_slug, ids} -> length(ids) end)

      eliminated =
        target_users
        |> Enum.take(4)
        |> Enum.map(&%{user_id: &1, username: "P#{&1}", stack_before_hand: 1_000})

      GenServer.cast(
        TournamentCoordinator.via(tournament.id),
        {:eliminations, target_slug, eliminated}
      )

      wait_for_sync(tournament.id)

      view = TournamentCoordinator.get_state(tournament.id)
      assert view.remaining == 13

      counts = view.tables |> Map.values() |> Enum.map(&length/1) |> Enum.sort()
      assert Enum.sum(counts) == 13
      assert Enum.max(counts) - Enum.min(counts) <= 1
    end
  end

  describe "blind levels and breaks" do
    test "advances levels, takes a break on schedule, and holds forever at the final level" do
      tournament =
        tournament_fixture(%{
          level_minutes: 12,
          break_every_minutes: 24,
          break_minutes: 5,
          blind_levels: [
            %{"small_blind" => 100, "big_blind" => 200},
            %{"small_blind" => 150, "big_blind" => 300},
            %{"small_blind" => 200, "big_blind" => 400}
          ]
        })

      users = for _ <- 1..2, do: user_fixture()
      tournament = start_tournament_for_test!(tournament, users)
      pid = GenServer.whereis(TournamentCoordinator.via(tournament.id))
      [slug] = Map.keys(TournamentCoordinator.get_state(tournament.id).tables)

      # Fires directly instead of waiting on the real (minutes-long) timer -
      # `handle_info(:advance, state)` doesn't care who sent the message.
      send(pid, :advance)
      view = TournamentCoordinator.get_state(tournament.id)
      assert view.current_level == 2
      assert view.small_blind == 150
      assert view.on_break == false
      assert TournamentTable.get_state(slug).small_blind == 150

      send(pid, :advance)
      view = TournamentCoordinator.get_state(tournament.id)
      assert view.current_level == 2
      assert view.on_break == true
      assert TournamentTable.get_state(slug).on_break == true

      send(pid, :advance)
      view = TournamentCoordinator.get_state(tournament.id)
      assert view.current_level == 3
      assert view.small_blind == 200
      assert view.on_break == false
      assert TournamentTable.get_state(slug).small_blind == 200
      assert TournamentTable.get_state(slug).on_break == false

      # Final level (3 of 3) reached - holds forever, a stray extra
      # `:advance` is a defensive no-op rather than crashing.
      send(pid, :advance)
      view = TournamentCoordinator.get_state(tournament.id)
      assert view.current_level == 3
      assert view.small_blind == 200
    end
  end

  # `:eliminations` is a cast - `get_state/1` is a synchronous call to the
  # same process, so once it replies every prior cast has already been
  # fully processed (GenServer callbacks are strictly serialized).
  defp wait_for_sync(tournament_id), do: TournamentCoordinator.get_state(tournament_id)
end
