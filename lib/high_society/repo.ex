defmodule HighSociety.Repo do
  use Ecto.Repo,
    otp_app: :high_society,
    adapter: Ecto.Adapters.Postgres
end
