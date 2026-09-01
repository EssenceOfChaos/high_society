defmodule HighSociety.Games.BattleshipMatchesSupervisorTest do
  # Touches the real, application-wide BattleshipMatchesSupervisor/Registry
  # names, so this needs the shared sandbox connection `async: false`
  # grants - matching `BattleshipMatchTest` and `PokerTableTest`.
  use HighSociety.DataCase, async: false

  alias HighSociety.Games.BattleshipMatch
  alias HighSociety.Games.BattleshipMatchesSupervisor
  alias HighSociety.Games.BattleshipMatchState

  import HighSociety.BattleshipFixtures

  describe "rehydrate_in_flight_matches!/0" do
    test "restarts a process for a match left in a non-terminal state" do
      creator = funded_user()
      slug = create_match_for_test!(creator, 100)

      # Simulate the app having restarted: stop the process without
      # touching its persisted row (unlike a normal test cleanup, a real
      # restart doesn't run any of this GenServer's own shutdown logic).
      pid = GenServer.whereis(BattleshipMatch.via(slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert GenServer.whereis(BattleshipMatch.via(slug)) == nil

      BattleshipMatchesSupervisor.rehydrate_in_flight_matches!()

      assert GenServer.whereis(BattleshipMatch.via(slug)) != nil
      assert BattleshipMatch.get_state(slug).status == :waiting_for_opponent
    end

    test "does not restart a match already in a terminal state" do
      creator = funded_user()
      joiner = funded_user()
      slug = create_match_for_test!(creator, 100)
      {:ok, _view} = BattleshipMatch.join(slug, joiner)
      {:ok, _view} = BattleshipMatch.forfeit(slug, creator.id)

      assert GenServer.whereis(BattleshipMatch.via(slug)) == nil

      BattleshipMatchesSupervisor.rehydrate_in_flight_matches!()

      assert GenServer.whereis(BattleshipMatch.via(slug)) == nil
      assert HighSociety.Repo.get_by!(BattleshipMatchState, slug: slug).status == "forfeited"
    end

    test "does not restart a cancelled match" do
      creator = funded_user()
      slug = create_match_for_test!(creator, 100)
      {:ok, _view} = BattleshipMatch.cancel(slug, creator.id)

      BattleshipMatchesSupervisor.rehydrate_in_flight_matches!()

      assert GenServer.whereis(BattleshipMatch.via(slug)) == nil
      assert HighSociety.Repo.get_by!(BattleshipMatchState, slug: slug).status == "cancelled"
    end
  end
end
