defmodule HighSociety.Encrypted.Date do
  @moduledoc """
  An encrypted-at-rest `Date` field, via `HighSociety.Vault`. Used for
  `HighSociety.Tournaments.PokerTournamentEntry.date_of_birth`.
  """
  use Cloak.Ecto.Date, vault: HighSociety.Vault
end
