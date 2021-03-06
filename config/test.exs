use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :high_society, HighSocietyWeb.Endpoint,
  http: [port: 4001],
  server: true

# Print only warnings and errors during test
config :logger, level: :warn

# Configure your database
config :high_society, HighSociety.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "high_society_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

  ## Configure Hound
  config :hound, driver: "chrome_driver", browser: "chrome_headless"

  ## Configure Argon2 for pw hashing
  config :argon2_elixir,
  t_cost: 1,
  m_cost: 8