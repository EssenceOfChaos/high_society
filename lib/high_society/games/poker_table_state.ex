defmodule HighSociety.Games.PokerTableState do
  @moduledoc """
  Persisted snapshot of one Poker table's durable state - who's seated
  where with how many chips, whose button it is, and (if a hand is in
  progress) the in-flight hand - so a restart or deploy can resume a table
  exactly where it left off instead of losing seated players' stacks.
  Owned entirely by `HighSociety.Games.PokerTable`; nothing else should
  read or write this table directly.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          slug: String.t(),
          seats: [map()],
          button_seat: integer() | nil,
          hand: map() | nil
        }

  schema "poker_table_states" do
    field :slug, :string
    field :seats, {:array, :map}, default: []
    field :button_seat, :integer
    field :hand, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(poker_table_state, attrs) do
    poker_table_state
    |> cast(attrs, [:slug, :seats, :button_seat, :hand])
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end
end
