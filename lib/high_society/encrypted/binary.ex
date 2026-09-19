defmodule HighSociety.Encrypted.Binary do
  @moduledoc """
  An encrypted-at-rest string field, via `HighSociety.Vault`. Used for the
  tournament KYC text fields (name, address, city, state, zip code) - see
  `HighSociety.Tournaments.PokerTournamentEntry`.
  """
  use Cloak.Ecto.Binary, vault: HighSociety.Vault
end
