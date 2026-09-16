defmodule HighSociety.Games.ZombieAttackGame do
  @moduledoc """
  Persisted Zombie Attack match - one row per user. Unlike Battleship's
  single jsonb blob holding the *entire* match, only checkpoint-level facts
  are ever persisted here: the wager/payout, the highest wave reached, and
  the wave schedule the client was given to simulate. Zombie positions,
  projectiles, defender placements, and everything else that happens
  moment-to-moment on the canvas never reaches the server at all - see
  `HighSociety.Games.ZombieAttack`'s moduledoc for what that implies about
  anti-cheat.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          status: String.t(),
          wager: integer(),
          payout: integer() | nil,
          wave_reached: integer(),
          wave_schedule: [map()],
          user_id: integer() | nil
        }

  @statuses ~w(in_progress won lost)

  schema "zombie_attack_games" do
    field :status, :string, default: "in_progress"
    field :wager, :integer
    field :payout, :integer
    field :wave_reached, :integer, default: 0
    field :wave_schedule, {:array, :map}, default: []

    belongs_to :user, HighSociety.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(zombie_attack_game, attrs) do
    zombie_attack_game
    |> cast(attrs, [:status, :wager, :payout, :wave_reached, :wave_schedule, :user_id])
    |> validate_required([:status, :wager, :wave_reached, :wave_schedule, :user_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:wager, greater_than: 0)
  end
end
