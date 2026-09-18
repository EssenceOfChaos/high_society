defmodule HighSociety.Tournaments.PokerTournament do
  @moduledoc """
  One scheduled/run of the poker tournament. Holds a snapshot of the blind
  schedule and timing (copied from `HighSociety.Games.TournamentBlinds` at
  creation - see `HighSociety.Tournaments.create_tournament/1`) so a later
  change to the defaults never retroactively alters a tournament that's
  already scheduled, running, or finished, plus the coordinator's live
  position in that schedule (`current_level`, `level_started_at`,
  `on_break`, `break_ends_at`) so a crash/deploy can resume it exactly
  where it left off - see `HighSociety.Games.TournamentCoordinator`, the
  sole owner of those four fields once a tournament is running.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias HighSociety.Games.TournamentBlinds

  @type t :: %__MODULE__{
          name: String.t(),
          status: String.t(),
          starting_stack: pos_integer(),
          level_minutes: pos_integer(),
          break_every_minutes: pos_integer(),
          break_minutes: pos_integer(),
          late_registration_minutes: pos_integer(),
          blind_levels: [TournamentBlinds.blind_level()],
          current_level: pos_integer(),
          level_started_at: DateTime.t() | nil,
          on_break: boolean(),
          break_ends_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil
        }

  @statuses ~w(scheduled running finished cancelled)

  schema "poker_tournaments" do
    field :name, :string
    field :status, :string, default: "scheduled"

    field :starting_stack, :integer
    field :level_minutes, :integer
    field :break_every_minutes, :integer
    field :break_minutes, :integer
    field :late_registration_minutes, :integer
    field :blind_levels, {:array, :map}

    field :current_level, :integer, default: 1
    field :level_started_at, :utc_datetime
    field :on_break, :boolean, default: false
    field :break_ends_at, :utc_datetime

    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for creating/editing a tournament's structure - only the
  fields an admin sets up front. `status` and the coordinator's live-run
  fields are never user-editable through this changeset; they're only
  ever touched by `HighSociety.Tournaments`/`TournamentCoordinator`.
  """
  def changeset(tournament, attrs) do
    tournament
    |> cast(attrs, [
      :name,
      :starting_stack,
      :level_minutes,
      :break_every_minutes,
      :break_minutes,
      :late_registration_minutes,
      :blind_levels
    ])
    |> validate_required([
      :name,
      :starting_stack,
      :level_minutes,
      :break_every_minutes,
      :break_minutes,
      :late_registration_minutes,
      :blind_levels
    ])
    |> validate_number(:starting_stack, greater_than: 0)
    |> validate_number(:level_minutes, greater_than: 0)
    |> validate_number(:break_every_minutes, greater_than: 0)
    |> validate_number(:break_minutes, greater_than: 0)
    |> validate_number(:late_registration_minutes, greater_than: 0)
    |> validate_length(:blind_levels, min: 1)
  end

  @doc false
  def status_changeset(tournament, attrs) do
    tournament
    |> cast(attrs, [
      :status,
      :current_level,
      :level_started_at,
      :on_break,
      :break_ends_at,
      :started_at,
      :finished_at
    ])
    |> validate_inclusion(:status, @statuses)
  end
end
