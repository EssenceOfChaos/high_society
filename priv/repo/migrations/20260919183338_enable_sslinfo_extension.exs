defmodule HighSociety.Repo.Migrations.EnableSslinfoExtension do
  use Ecto.Migration

  # Read-only diagnostic extension (exposes ssl_is_used()/ssl_cipher() etc.) -
  # doesn't touch app tables or change connection behavior itself. Lets
  # ecto_psql_extras' ssl_used check on the LiveDashboard actually confirm
  # the Repo's `ssl: true` (config/runtime.exs) is really encrypting
  # connections, instead of reporting "can't check".
  def change do
    execute "CREATE EXTENSION IF NOT EXISTS sslinfo", "DROP EXTENSION IF EXISTS sslinfo"
  end
end
