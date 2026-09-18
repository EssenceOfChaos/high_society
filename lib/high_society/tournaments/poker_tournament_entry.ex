defmodule HighSociety.Tournaments.PokerTournamentEntry do
  @moduledoc """
  One user's registration/entry for one specific
  `HighSociety.Tournaments.PokerTournament` run. `ethereum_address` is
  opt-in and only ever used as a place a human would manually send a prize
  after the tournament - nothing in this app reads it to move crypto on its
  own, so there's no wallet/key handling here to secure.

  `bought_in_at`/`eliminated_at`/`finish_place` are never user-editable -
  they're only ever set by `HighSociety.Tournaments`/
  `HighSociety.Games.TournamentCoordinator` as the tournament actually
  runs, through `placement_changeset/2` rather than the public
  `changeset/2` used by the registration form.
  """
  @type t :: %__MODULE__{
          user_id: pos_integer(),
          tournament_id: pos_integer(),
          ethereum_address: String.t() | nil,
          bought_in_at: DateTime.t() | nil,
          eliminated_at: DateTime.t() | nil,
          finish_place: pos_integer() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  use Ecto.Schema
  import Ecto.Changeset

  # 0x + 40 hex chars - the standard Ethereum address format. Deliberately
  # not checking EIP-55 checksum casing: that's a client-side convenience,
  # not part of the address itself, and rejecting a validly-cased address
  # someone pasted in lowercase would just be user-hostile here.
  @ethereum_address_format ~r/^0x[0-9a-fA-F]{40}$/

  schema "poker_tournament_entries" do
    field :ethereum_address, :string
    field :bought_in_at, :utc_datetime
    field :eliminated_at, :utc_datetime
    field :finish_place, :integer

    belongs_to :user, HighSociety.Accounts.User
    belongs_to :tournament, HighSociety.Tournaments.PokerTournament

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for the registration form - only ever touches `user_id`
  (pre-set on the struct by the caller, same as `tournament_id`) and the
  optional Ethereum address.
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:user_id, :tournament_id, :ethereum_address])
    |> update_change(:ethereum_address, &blank_to_nil/1)
    |> validate_required([:user_id, :tournament_id])
    |> validate_format(:ethereum_address, @ethereum_address_format,
      message: "doesn't look like a valid Ethereum address (0x followed by 40 hex characters)"
    )
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tournament_id)
    |> unique_constraint([:tournament_id, :user_id],
      name: :poker_tournament_entries_tournament_id_user_id_index
    )
  end

  @doc """
  A changeset for the tournament engine to record a buy-in, elimination,
  or final placement - never exposed to the registration form.
  """
  def placement_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:bought_in_at, :eliminated_at, :finish_place])
    |> validate_number(:finish_place, greater_than: 0)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
