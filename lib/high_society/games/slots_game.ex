defmodule HighSociety.Games.SlotsGame do
  @moduledoc """
  Persisted result of the user's latest Slots spin. Unlike Blackjack (whose
  row survives mid-round so the LiveView can resume it), a spin always
  resolves fully server-side in one step - the only state that needs to
  carry forward between spins is whether a free-spins round is under way,
  captured by `free_spins_remaining`/`free_spin_multiplier`/
  `triggering_wager`. There's one row per user, replaced on every spin.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          grid: [String.t()],
          wins: [map()],
          wager: integer(),
          total_win: integer(),
          free_spins_remaining: integer(),
          free_spin_multiplier: integer(),
          triggering_wager: integer() | nil,
          bonus_triggered: boolean(),
          spins_taken: integer(),
          user_id: integer() | nil
        }

  schema "slots_games" do
    field :grid, {:array, :string}, default: []
    field :wins, {:array, :map}, default: []
    field :wager, :integer
    field :total_win, :integer, default: 0
    field :free_spins_remaining, :integer, default: 0
    field :free_spin_multiplier, :integer, default: 1
    field :triggering_wager, :integer
    field :bonus_triggered, :boolean, default: false
    field :spins_taken, :integer, default: 0

    belongs_to :user, HighSociety.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(slots_game, attrs) do
    slots_game
    |> cast(attrs, [
      :grid,
      :wins,
      :wager,
      :total_win,
      :free_spins_remaining,
      :free_spin_multiplier,
      :triggering_wager,
      :bonus_triggered,
      :spins_taken,
      :user_id
    ])
    |> validate_required([:grid, :wager, :user_id])
    |> validate_number(:wager, greater_than: 0)
  end
end
