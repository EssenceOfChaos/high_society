defmodule HighSociety.Games.TournamentTableState do
  @moduledoc """
  Persisted snapshot of one live tournament table - same durable shape as
  `HighSociety.Games.PokerTableState` (who's seated where, whose button it
  is, the in-progress hand), plus the one thing cash tables never need: a
  `status` distinguishing an `"active"` table from a `"closed"` one (a
  table that emptied out via elimination/rebalancing, or the tournament
  ending), mirroring `HighSociety.Games.BattleshipMatchState`. Owned
  entirely by `HighSociety.Games.TournamentTable`; nothing else should
  read or write this table directly.
  `HighSociety.Games.TournamentTablesSupervisor` scans for `"active"` rows
  at boot to restart their processes, since a dynamically-supervised
  tournament table (unlike Poker's fixed cash tables) has nothing else
  that would bring it back automatically.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          slug: String.t(),
          tournament_id: integer(),
          status: String.t(),
          seats: [map()],
          button_seat: integer() | nil,
          hand: map() | nil
        }

  @statuses ~w(active closed)

  schema "poker_tournament_table_states" do
    field :slug, :string
    field :status, :string, default: "active"
    field :seats, {:array, :map}, default: []
    field :button_seat, :integer
    field :hand, :map

    belongs_to :tournament, HighSociety.Tournaments.PokerTournament

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(table_state, attrs) do
    table_state
    |> cast(attrs, [:slug, :tournament_id, :status, :seats, :button_seat, :hand])
    |> validate_required([:slug, :tournament_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:tournament_id)
  end
end
