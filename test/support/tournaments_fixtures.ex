defmodule HighSociety.TournamentsFixtures do
  @moduledoc """
  Test helpers for poker tournaments - creating a tournament row to
  register against, and creating/seating a live `TournamentTable`. Unlike
  Poker's cash tables (one long-lived GenServer per fixed table, shared
  across the whole test suite - see `HighSociety.PokerFixtures`), a
  tournament table is its own short-lived, dynamically-supervised process
  created fresh by whichever test needs it - same shape as
  `HighSociety.BattleshipFixtures` - so there's no shared state to reset
  between tests, just a defensive stop in `on_exit`.
  """

  import Ecto.Query

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games.TournamentCoordinator
  alias HighSociety.Games.TournamentTable
  alias HighSociety.Games.TournamentTableState
  alias HighSociety.Repo
  alias HighSociety.Tournaments

  @doc "A tournament, `scheduled` by default, using `TournamentBlinds`' defaults unless overridden."
  def tournament_fixture(attrs \\ %{}) do
    {:ok, tournament} =
      attrs
      |> Enum.into(%{name: "High Society Poker Tournament"})
      |> Tournaments.create_tournament()

    tournament
  end

  @doc "Creates a fresh, empty table under `tournament`, stopping it after the test."
  @spec tournament_table_fixture!(Tournaments.PokerTournament.t(), String.t() | nil) ::
          String.t()
  def tournament_table_fixture!(tournament, slug \\ nil) do
    slug = slug || "table-#{System.unique_integer([:positive, :monotonic])}"
    {:ok, _pid} = TournamentTable.create!(tournament.id, slug)
    stop_table_after_test!(slug)
    slug
  end

  @doc "Stops `slug`'s table process (if any) after the current test."
  @spec stop_table_after_test!(String.t()) :: :ok
  def stop_table_after_test!(slug) do
    ExUnit.Callbacks.on_exit(fn ->
      case GenServer.whereis(TournamentTable.via(slug)) do
        nil -> :ok
        pid -> try_stop(pid)
      end
    end)
  end

  @doc """
  Registers each of `users` for `tournament`, then does what
  `HighSociety.Tournaments.start!/1` (phase 4) will eventually do:
  flips the tournament to `running` as of `started_at` (defaults to now)
  and starts its coordinator - stopping the coordinator and every table
  it creates after the test.
  """
  @spec start_tournament_for_test!(
          Tournaments.PokerTournament.t(),
          [Accounts.User.t()],
          keyword()
        ) ::
          Tournaments.PokerTournament.t()
  def start_tournament_for_test!(tournament, users, opts \\ []) do
    Enum.each(users, fn user ->
      {:ok, _entry} = Tournaments.register(Scope.for_user(user), tournament, %{})
    end)

    started_at = Keyword.get(opts, :started_at, DateTime.utc_now(:second))

    Repo.update_all(
      from(t in Tournaments.PokerTournament, where: t.id == ^tournament.id),
      set: [
        status: "running",
        started_at: started_at,
        level_started_at: started_at,
        current_level: 1
      ]
    )

    tournament = Repo.get!(Tournaments.PokerTournament, tournament.id)
    {:ok, _pid} = HighSociety.Games.TournamentsSupervisor.start_coordinator(tournament.id)
    stop_tournament_after_test!(tournament.id)
    tournament
  end

  @doc "Stops `tournament_id`'s coordinator and every table it created, after the current test."
  @spec stop_tournament_after_test!(pos_integer()) :: :ok
  def stop_tournament_after_test!(tournament_id) do
    ExUnit.Callbacks.on_exit(fn ->
      case GenServer.whereis(TournamentCoordinator.via(tournament_id)) do
        nil -> :ok
        pid -> try_stop(pid)
      end

      TournamentTableState
      |> where([t], t.tournament_id == ^tournament_id)
      |> Repo.all()
      |> Enum.each(fn %{slug: slug} ->
        case GenServer.whereis(TournamentTable.via(slug)) do
          nil -> :ok
          pid -> try_stop(pid)
        end
      end)
    end)
  end

  defp try_stop(pid) do
    GenServer.stop(pid)
  catch
    :exit, _ -> :ok
  end
end
