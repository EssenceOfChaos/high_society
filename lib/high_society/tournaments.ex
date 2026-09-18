defmodule HighSociety.Tournaments do
  @moduledoc """
  Registration and setup for poker tournaments. An account is required to
  enter (see the `:require_authenticated_user` route), and an Ethereum
  address is optional - it's only where a human would manually send a
  prize after the tournament, so there's no on-chain code anywhere in this
  context. Running a tournament once it's started (blind levels, seating,
  eliminations, results) is owned by `HighSociety.Games.TournamentCoordinator`
  and `HighSociety.Games.TournamentTable`, not this module.
  """

  import Ecto.Query

  alias HighSociety.Accounts.Scope
  alias HighSociety.Games.TournamentBlinds
  alias HighSociety.Games.TournamentsSupervisor
  alias HighSociety.Repo
  alias HighSociety.Tournaments.Notifier
  alias HighSociety.Tournaments.PokerTournament
  alias HighSociety.Tournaments.PokerTournamentEntry

  @doc """
  The tournament to show on the registration page right now: the soonest
  tournament still `scheduled`, or - if none is scheduled - a `running`
  tournament still inside its late-registration window (see
  `TournamentBlinds.late_registration_minutes/0`). `nil` if neither
  exists, in which case the registration page shows an empty state instead
  of a form.
  """
  @spec current_tournament() :: PokerTournament.t() | nil
  def current_tournament do
    next_scheduled_tournament() || currently_registrable_running_tournament()
  end

  defp next_scheduled_tournament do
    Repo.one(
      from t in PokerTournament,
        where: t.status == "scheduled",
        order_by: [asc: t.inserted_at],
        limit: 1
    )
  end

  defp currently_registrable_running_tournament do
    now = DateTime.utc_now()

    PokerTournament
    |> where([t], t.status == "running")
    |> Repo.all()
    |> Enum.find(&late_registration_open?(&1, now))
  end

  defp late_registration_open?(%PokerTournament{started_at: nil}, _now), do: false

  defp late_registration_open?(%PokerTournament{} = tournament, now) do
    deadline =
      DateTime.add(tournament.started_at, tournament.late_registration_minutes * 60, :second)

    DateTime.compare(now, deadline) == :lt
  end

  @doc """
  Creates a new tournament. `attrs` overrides any of `TournamentBlinds`'
  defaults (starting stack, level/break timing, blind schedule), which are
  otherwise snapshotted onto the row as-is so a later change to the
  defaults never retroactively alters this tournament.
  """
  @spec create_tournament(map()) :: {:ok, PokerTournament.t()} | {:error, Ecto.Changeset.t()}
  def create_tournament(attrs \\ %{}) do
    default_tournament_struct()
    |> PokerTournament.changeset(attrs)
    |> Repo.insert()
  end

  # A base struct with defaults pre-set as its own field values, rather
  # than a map of defaults merged into `attrs` before casting - `attrs`
  # comes from either a LiveView form (string keys) or a test/fixture
  # caller (atom keys), and `Ecto.Changeset.cast/4` rejects a map that
  # mixes the two, which a plain `Map.merge/2` of two differently-keyed
  # maps could otherwise silently produce.
  defp default_tournament_struct do
    %PokerTournament{
      starting_stack: TournamentBlinds.starting_stack(),
      level_minutes: TournamentBlinds.level_minutes(),
      break_every_minutes: TournamentBlinds.break_every_minutes(),
      break_minutes: TournamentBlinds.break_minutes(),
      late_registration_minutes: TournamentBlinds.late_registration_minutes(),
      blind_levels: blind_levels_json(TournamentBlinds.default_schedule())
    }
  end

  # Stored with string keys up front (rather than relying on jsonb to
  # silently round-trip atom keys as strings later) - the same explicit
  # atom/string boundary convention `PokerTable` uses for its persisted
  # hand JSON.
  defp blind_levels_json(levels),
    do:
      Enum.map(levels, fn %{small_blind: sb, big_blind: bb} ->
        %{"small_blind" => sb, "big_blind" => bb}
      end)

  @doc """
  The scoped user's entry for `tournament`, or `nil` if they haven't
  registered for it.
  """
  @spec get_entry(Scope.t(), PokerTournament.t()) :: PokerTournamentEntry.t() | nil
  def get_entry(%Scope{} = scope, %PokerTournament{} = tournament) do
    Repo.get_by(PokerTournamentEntry, user_id: scope.user.id, tournament_id: tournament.id)
  end

  @doc """
  A changeset for the scoped user's entry (existing or a fresh one) into
  `tournament`, for rendering the registration form.
  """
  @spec change_entry(Scope.t(), PokerTournament.t(), map()) :: Ecto.Changeset.t()
  def change_entry(%Scope{} = scope, %PokerTournament{} = tournament, attrs \\ %{}) do
    entry(scope, tournament) |> PokerTournamentEntry.changeset(attrs)
  end

  @doc """
  Registers the scoped user for `tournament`, or updates their existing
  entry (e.g. changing the Ethereum address) if they've already
  registered. Sends a confirmation email either way.
  """
  @spec register(Scope.t(), PokerTournament.t(), map()) ::
          {:ok, PokerTournamentEntry.t()} | {:error, Ecto.Changeset.t()}
  def register(%Scope{} = scope, %PokerTournament{} = tournament, attrs) do
    entry(scope, tournament)
    |> PokerTournamentEntry.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, entry} ->
        Notifier.deliver_registration_confirmation(scope.user, entry)
        {:ok, entry}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp entry(%Scope{} = scope, %PokerTournament{} = tournament) do
    get_entry(scope, tournament) ||
      %PokerTournamentEntry{user_id: scope.user.id, tournament_id: tournament.id}
  end

  @doc "Every tournament, most recently created first - for the admin list."
  @spec list_tournaments() :: [PokerTournament.t()]
  def list_tournaments do
    # `id` breaks a tie between two tournaments created in the same second
    # (`inserted_at` is `:utc_datetime`, second precision) - `id` is
    # otherwise monotonic with creation order.
    Repo.all(from t in PokerTournament, order_by: [desc: t.inserted_at, desc: t.id])
  end

  @doc "Raises if `id` doesn't exist."
  @spec get_tournament!(pos_integer()) :: PokerTournament.t()
  def get_tournament!(id), do: Repo.get!(PokerTournament, id)

  @doc """
  `tournament`'s entries, finished players first (best place first), then
  still-active entrants - the results/standings page, and the admin's
  manual-payout checklist for 1st/2nd.
  """
  @spec standings(PokerTournament.t()) :: [PokerTournamentEntry.t()]
  def standings(%PokerTournament{} = tournament) do
    PokerTournamentEntry
    |> where([e], e.tournament_id == ^tournament.id)
    |> order_by([e], asc_nulls_last: e.finish_place)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Starts `tournament`: flips it to `running` as of now and starts its
  coordinator (`HighSociety.Games.TournamentCoordinator`), which does the
  actual initial seating. A guarded `update_all` (matching
  `HighSociety.Accounts.adjust_tokens_balance/4`'s pattern) means two
  admins clicking "Start" at once can't both succeed.
  """
  @spec start!(PokerTournament.t()) ::
          {:ok, PokerTournament.t()} | {:error, :already_started | :not_enough_entrants}
  def start!(%PokerTournament{} = tournament) do
    cond do
      tournament.status != "scheduled" ->
        {:error, :already_started}

      entrant_count(tournament) < 2 ->
        {:error, :not_enough_entrants}

      true ->
        now = DateTime.utc_now(:second)

        {count, _} =
          Repo.update_all(
            from(t in PokerTournament, where: t.id == ^tournament.id and t.status == "scheduled"),
            set: [status: "running", started_at: now, level_started_at: now, current_level: 1]
          )

        if count == 1 do
          {:ok, _pid} = TournamentsSupervisor.start_coordinator(tournament.id)
          {:ok, get_tournament!(tournament.id)}
        else
          {:error, :already_started}
        end
    end
  end

  defp entrant_count(%PokerTournament{} = tournament) do
    Repo.aggregate(
      from(e in PokerTournamentEntry, where: e.tournament_id == ^tournament.id),
      :count
    )
  end

  @doc """
  A changeset for creating a new tournament, pre-filled with
  `TournamentBlinds`' defaults - the admin form only exposes the numeric
  timing knobs for editing, the blind schedule itself always starts from
  the current default (a fuller custom-schedule editor is future scope).
  """
  @spec change_tournament(map()) :: Ecto.Changeset.t()
  def change_tournament(attrs \\ %{}) do
    PokerTournament.changeset(default_tournament_struct(), attrs)
  end
end
