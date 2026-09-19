defmodule HighSociety.Tournaments.PokerTournamentEntry do
  @moduledoc """
  One user's registration/entry for one specific
  `HighSociety.Tournaments.PokerTournament` run. `ethereum_address` and
  the KYC fields (`first_name` through `date_of_birth`) are all opt-in at
  registration time - nothing in this app moves crypto or verifies
  identity on its own. The KYC fields exist only because a 1st/2nd place
  winner is required to provide them within 7 days of the tournament
  ending in order to actually receive their prize (sanctions/anti-money-
  laundering screening before any payout - see the "Prize Claim &
  Compliance Requirements" section of `/tournament/rules`); everyone
  else's entry never needs them filled in at all. They're encrypted at
  rest (`HighSociety.Encrypted.Binary`/`Date`, via `HighSociety.Vault`)
  since this is real PII, unlike anything else this app stores.

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
          first_name: String.t() | nil,
          last_name: String.t() | nil,
          address: String.t() | nil,
          city: String.t() | nil,
          state: String.t() | nil,
          zip_code: String.t() | nil,
          date_of_birth: Date.t() | nil,
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

  @kyc_text_fields ~w(first_name last_name address city state zip_code)a

  schema "poker_tournament_entries" do
    field :ethereum_address, :string
    field :first_name, HighSociety.Encrypted.Binary
    field :last_name, HighSociety.Encrypted.Binary
    field :address, HighSociety.Encrypted.Binary
    field :city, HighSociety.Encrypted.Binary
    field :state, HighSociety.Encrypted.Binary
    field :zip_code, HighSociety.Encrypted.Binary
    field :date_of_birth, HighSociety.Encrypted.Date
    field :bought_in_at, :utc_datetime
    field :eliminated_at, :utc_datetime
    field :finish_place, :integer

    belongs_to :user, HighSociety.Accounts.User
    belongs_to :tournament, HighSociety.Tournaments.PokerTournament

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for the registration form - `user_id`/`tournament_id` (both
  pre-set on the struct by the caller), the optional Ethereum address,
  and the optional KYC fields (all-or-nothing isn't enforced - a player
  can fill in as few or as many as they like, any time before or after
  the tournament).
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :user_id,
      :tournament_id,
      :ethereum_address,
      :date_of_birth | @kyc_text_fields
    ])
    |> update_change(:ethereum_address, &blank_to_nil/1)
    |> blank_text_fields_to_nil()
    |> validate_required([:user_id, :tournament_id])
    |> validate_format(:ethereum_address, @ethereum_address_format,
      message: "doesn't look like a valid Ethereum address (0x followed by 40 hex characters)"
    )
    |> validate_date_of_birth()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tournament_id)
    |> unique_constraint([:tournament_id, :user_id],
      name: :poker_tournament_entries_tournament_id_user_id_index
    )
  end

  defp blank_text_fields_to_nil(changeset) do
    Enum.reduce(@kyc_text_fields, changeset, &update_change(&2, &1, fn v -> blank_to_nil(v) end))
  end

  defp validate_date_of_birth(changeset) do
    validate_change(changeset, :date_of_birth, fn :date_of_birth, dob ->
      today = Date.utc_today()

      cond do
        Date.compare(dob, today) != :lt ->
          [date_of_birth: "can't be in the future"]

        age_in_years(dob, today) < 18 ->
          [date_of_birth: "must be at least 18 years old"]

        true ->
          []
      end
    end)
  end

  defp age_in_years(%Date{} = dob, %Date{} = today) do
    years = today.year - dob.year
    if {today.month, today.day} < {dob.month, dob.day}, do: years - 1, else: years
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
