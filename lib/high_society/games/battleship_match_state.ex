defmodule HighSociety.Games.BattleshipMatchState do
  @moduledoc """
  Persisted snapshot of one live Battleship match - who's seated in each
  of the two seats, the wager, and (once placement has started) the full
  `HighSociety.Games.Battleship` match as jsonb. Owned entirely by
  `HighSociety.Games.BattleshipMatch`; nothing else should read or write
  this table directly. Survives a crash or deploy: `BattleshipMatch.init/1`
  reloads it, and `HighSociety.Games.BattleshipMatchesSupervisor` scans
  for any non-terminal row at boot to restart its process (unlike Poker's
  fixed tables, a dynamically-supervised match has nothing else that
  would bring it back automatically).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          slug: String.t(),
          wager: integer(),
          status: String.t(),
          seat_0_user_id: integer() | nil,
          seat_1_user_id: integer() | nil,
          battleship: map() | nil
        }

  @statuses ~w(waiting_for_opponent placing_fleets player_turn opponent_turn player_won opponent_won forfeited cancelled)

  schema "battleship_match_states" do
    field :slug, :string
    field :wager, :integer
    field :status, :string, default: "waiting_for_opponent"
    field :battleship, :map

    belongs_to :seat_0_user, HighSociety.Accounts.User, foreign_key: :seat_0_user_id
    belongs_to :seat_1_user, HighSociety.Accounts.User, foreign_key: :seat_1_user_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(match_state, attrs) do
    match_state
    |> cast(attrs, [:slug, :wager, :status, :seat_0_user_id, :seat_1_user_id, :battleship])
    |> validate_required([:slug, :wager, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug)
  end
end
