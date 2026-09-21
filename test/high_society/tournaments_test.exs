defmodule HighSociety.TournamentsTest do
  # `start!/1` starts a real, dynamically-supervised `TournamentCoordinator`
  # - like `HighSociety.Games.BattleshipMatchesTest`, that needs the
  # sandbox connection shared (`shared: not tags[:async]` in
  # `HighSociety.DataCase`), which only happens when `async: false`.
  use HighSociety.DataCase, async: false

  import HighSociety.AccountsFixtures
  import HighSociety.TournamentsFixtures
  import Swoosh.TestAssertions

  alias HighSociety.Tournaments

  setup do
    user = user_fixture()
    # user_fixture/1 itself sends a login-confirmation email and (since this
    # is the account's first confirmation) a welcome email - drain both so
    # each test's assert_email_sent only ever sees its own registration
    # email (Swoosh's test assertions consume the mailbox in send order).
    assert_email_sent(subject: "Confirmation instructions")
    assert_email_sent(subject: "Welcome to HighSociety!")

    %{
      user: user,
      scope: HighSociety.Accounts.Scope.for_user(user),
      tournament: tournament_fixture()
    }
  end

  describe "get_entry/2" do
    test "nil when the user hasn't registered", %{scope: scope, tournament: tournament} do
      assert Tournaments.get_entry(scope, tournament) == nil
    end

    test "the user's entry once registered", %{scope: scope, tournament: tournament} do
      {:ok, entry} = Tournaments.register(scope, tournament, %{})
      assert Tournaments.get_entry(scope, tournament).id == entry.id
    end
  end

  describe "register/3" do
    test "registers without an Ethereum address", %{
      scope: scope,
      tournament: tournament,
      user: user
    } do
      assert {:ok, entry} = Tournaments.register(scope, tournament, %{})
      assert entry.user_id == user.id
      assert entry.tournament_id == tournament.id
      assert entry.ethereum_address == nil

      assert_tournament_confirmation_sent(user.email)
    end

    test "registers with a valid Ethereum address", %{scope: scope, tournament: tournament} do
      address = "0x" <> String.duplicate("a", 40)

      assert {:ok, entry} =
               Tournaments.register(scope, tournament, %{"ethereum_address" => address})

      assert entry.ethereum_address == address
    end

    test "rejects a malformed Ethereum address", %{scope: scope, tournament: tournament} do
      assert {:error, changeset} =
               Tournaments.register(scope, tournament, %{"ethereum_address" => "not-an-address"})

      assert %{ethereum_address: ["doesn't look like a valid Ethereum address" <> _]} =
               errors_on(changeset)

      refute_tournament_confirmation_sent()
    end

    test "treats a blank Ethereum address as none provided", %{
      scope: scope,
      tournament: tournament
    } do
      assert {:ok, entry} =
               Tournaments.register(scope, tournament, %{"ethereum_address" => "   "})

      assert entry.ethereum_address == nil
    end

    test "updates the existing entry instead of creating a second one", %{
      scope: scope,
      tournament: tournament,
      user: user
    } do
      address = "0x" <> String.duplicate("a", 40)
      new_address = "0x" <> String.duplicate("b", 40)

      assert {:ok, first} =
               Tournaments.register(scope, tournament, %{"ethereum_address" => address})

      assert {:ok, updated} =
               Tournaments.register(scope, tournament, %{"ethereum_address" => new_address})

      assert first.id == updated.id
      assert updated.ethereum_address == new_address

      assert Repo.aggregate(
               HighSociety.Tournaments.PokerTournamentEntry,
               :count
             ) == 1

      assert_tournament_confirmation_sent(user.email)
      assert_tournament_confirmation_sent(user.email)
    end

    test "the same user can register for two different tournaments", %{
      scope: scope,
      tournament: tournament,
      user: user
    } do
      other_tournament = tournament_fixture(%{name: "Another Tournament"})

      assert {:ok, _entry} = Tournaments.register(scope, tournament, %{})
      assert {:ok, _entry} = Tournaments.register(scope, other_tournament, %{})

      assert Repo.aggregate(HighSociety.Tournaments.PokerTournamentEntry, :count) == 2

      assert_tournament_confirmation_sent(user.email)
      assert_tournament_confirmation_sent(user.email)
    end
  end

  describe "change_entry/3" do
    test "an unpersisted changeset for a user who hasn't registered", %{
      scope: scope,
      tournament: tournament
    } do
      changeset = Tournaments.change_entry(scope, tournament)
      refute changeset.data.id
    end

    test "a changeset for the user's existing entry once registered", %{
      scope: scope,
      tournament: tournament
    } do
      {:ok, entry} = Tournaments.register(scope, tournament, %{})
      changeset = Tournaments.change_entry(scope, tournament)
      assert changeset.data.id == entry.id
    end
  end

  describe "current_tournament/0" do
    test "the soonest scheduled tournament", %{tournament: tournament} do
      assert Tournaments.current_tournament().id == tournament.id
    end

    test "nil when nothing is scheduled or registrable" do
      # `tournament` from setup would otherwise satisfy this - cancel it out
      # of the way by marking it finished directly.
      Repo.update_all(HighSociety.Tournaments.PokerTournament, set: [status: "finished"])
      assert Tournaments.current_tournament() == nil
    end
  end

  describe "scheduled_countdown?/1" do
    test "false when nothing is scheduled" do
      refute Tournaments.scheduled_countdown?(nil)
    end

    test "false for a scheduled tournament with no announced start time", %{
      tournament: tournament
    } do
      assert tournament.scheduled_start_at == nil
      refute Tournaments.scheduled_countdown?(tournament)
    end

    test "true for a scheduled tournament with an announced start time" do
      tournament = tournament_fixture(%{scheduled_start_at: ~U[2026-10-30 21:00:00Z]})
      assert Tournaments.scheduled_countdown?(tournament)
    end

    test "false once the tournament is running, even with a start time set", %{
      tournament: tournament
    } do
      {:ok, tournament} =
        tournament
        |> HighSociety.Tournaments.PokerTournament.status_changeset(%{
          status: "running",
          started_at: DateTime.utc_now()
        })
        |> Repo.update()

      refute Tournaments.scheduled_countdown?(tournament)
    end
  end

  describe "list_tournaments/0 and get_tournament!/1" do
    test "lists every tournament, most recent first", %{tournament: tournament} do
      other = tournament_fixture(%{name: "Later Tournament"})
      ids = Tournaments.list_tournaments() |> Enum.map(& &1.id)
      assert ids == [other.id, tournament.id]
    end

    test "fetches a single tournament by id", %{tournament: tournament} do
      assert Tournaments.get_tournament!(tournament.id).id == tournament.id
    end
  end

  describe "start!/1" do
    test "rejects a tournament with fewer than 2 entrants", %{
      tournament: tournament,
      scope: scope
    } do
      {:ok, _entry} = Tournaments.register(scope, tournament, %{})
      assert {:error, :not_enough_entrants} = Tournaments.start!(tournament)
    end

    test "starts a tournament with 2+ entrants and seats them", %{
      tournament: tournament,
      scope: scope
    } do
      {:ok, _entry} = Tournaments.register(scope, tournament, %{})
      other_user = user_fixture()

      {:ok, _entry} =
        Tournaments.register(HighSociety.Accounts.Scope.for_user(other_user), tournament, %{})

      assert {:ok, started} = Tournaments.start!(tournament)
      stop_tournament_after_test!(started.id)

      assert started.status == "running"
      assert started.started_at != nil
      assert started.current_level == 1

      coordinator_view = HighSociety.Games.TournamentCoordinator.get_state(started.id)
      assert coordinator_view.remaining == 2
    end

    test "rejects starting an already-running tournament", %{tournament: tournament, scope: scope} do
      {:ok, _entry} = Tournaments.register(scope, tournament, %{})
      other_user = user_fixture()

      {:ok, _entry} =
        Tournaments.register(HighSociety.Accounts.Scope.for_user(other_user), tournament, %{})

      assert {:ok, started} = Tournaments.start!(tournament)
      stop_tournament_after_test!(started.id)

      assert {:error, :already_started} = Tournaments.start!(started)
    end
  end

  describe "standings/1" do
    test "orders finished players by place, active entrants last", %{tournament: tournament} do
      users = for _ <- 1..3, do: user_fixture()
      [placed_second, placed_first, still_playing] = users

      Enum.each(users, fn user ->
        {:ok, _entry} =
          Tournaments.register(HighSociety.Accounts.Scope.for_user(user), tournament, %{})
      end)

      set_finish_place!(tournament, placed_first, 1)
      set_finish_place!(tournament, placed_second, 2)

      standings = Tournaments.standings(tournament)

      assert Enum.map(standings, & &1.user_id) == [
               placed_first.id,
               placed_second.id,
               still_playing.id
             ]
    end
  end

  defp set_finish_place!(tournament, user, place) do
    Repo.get_by!(HighSociety.Tournaments.PokerTournamentEntry,
      tournament_id: tournament.id,
      user_id: user.id
    )
    |> HighSociety.Tournaments.PokerTournamentEntry.placement_changeset(%{finish_place: place})
    |> Repo.update!()
  end

  # `user_fixture/1` (used in `setup`) itself sends a login-confirmation
  # email, so a bare `to: user.email` matcher can't tell that apart from an
  # actual tournament confirmation - match on the subject too.
  defp assert_tournament_confirmation_sent(email) do
    assert_email_sent(
      to: email,
      subject: "You're registered for the High Society poker tournament"
    )
  end

  defp refute_tournament_confirmation_sent do
    refute_email_sent(subject: "You're registered for the High Society poker tournament")
  end
end
