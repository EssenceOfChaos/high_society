# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :high_society, :scopes,
  user: [
    default: true,
    module: HighSociety.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: HighSociety.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :high_society,
  ecto_repos: [HighSociety.Repo],
  generators: [timestamp_type: :utc_datetime]

# Off everywhere except :dev (see config/dev.exs) - see
# `HighSociety.Games.PokerBots` for what this turns on.
config :high_society, :poker_bots_enabled, false

# Configure the endpoint
config :high_society, HighSocietyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HighSocietyWeb.ErrorHTML, json: HighSocietyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: HighSociety.PubSub,
  live_view: [signing_salt: "VAkBW76b"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :high_society, HighSociety.Mailer, adapter: Swoosh.Adapters.Local
config :high_society, :mailer_from_email, "onboarding@resend.dev"
config :high_society, :support_email, "support@highsociety.cc"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  high_society: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  high_society: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
