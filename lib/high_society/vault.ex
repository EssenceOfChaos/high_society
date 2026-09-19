defmodule HighSociety.Vault do
  @moduledoc """
  Encrypts/decrypts the poker tournament KYC fields (legal name, address,
  date of birth - see `HighSociety.Tournaments.PokerTournamentEntry`) at
  rest, via `HighSociety.Encrypted.Binary`/`HighSociety.Encrypted.Date`.
  Nothing else in this app is encrypted at rest; this exists specifically
  because those fields are real PII collected only to satisfy the
  sanctions/KYC compliance requirement in the tournament's "Prize Claim &
  Compliance Requirements" rule (see `/tournament/rules`).

  Configured entirely via `config :high_society, HighSociety.Vault,
  ciphers: [...]` - a real AES-256 key from the `KYC_ENCRYPTION_KEY`
  environment variable in prod (see `config/runtime.exs`, which raises on
  boot if it's unset), and a fixed, non-secret key in dev/test (see
  `config/dev.exs`/`config/test.exs`) so nothing needs a real key to run
  locally. Same env-var-in-prod pattern this app already uses for
  `:resend_webhook_secret`.
  """
  use Cloak.Vault, otp_app: :high_society
end
