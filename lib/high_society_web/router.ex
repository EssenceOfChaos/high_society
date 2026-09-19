defmodule HighSocietyWeb.Router do
  use HighSocietyWeb, :router

  import HighSocietyWeb.UserAuth
  # sobelow_skip ["Config.Headers"]
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug HighSocietyWeb.Plugs.CaptureGeo
    plug :fetch_live_flash
    plug :put_root_layout, html: {HighSocietyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :fetch_current_scope_for_user
    plug :put_csp_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # heroicons are compiled into app.css as CSS `mask-image` data: URIs, which the
  # `img-src` directive governs; the inline theme script in root.html.heex needs a
  # per-request nonce since `script-src` has no 'unsafe-inline'. The googletagmanager.com/
  # google-analytics.com entries are for the Google Analytics gtag.js snippet (see
  # HighSocietyWeb.Layouts.google_analytics_id/0) - harmless to allow even when no
  # GOOGLE_ANALYTICS_ID is configured, since nothing then requests those hosts.
  defp put_csp_headers(conn, _opts) do
    nonce = Base.encode64(:crypto.strong_rand_bytes(16))

    conn
    |> assign(:csp_nonce, nonce)
    |> put_secure_browser_headers(%{
      "content-security-policy" =>
        "default-src 'self'; " <>
          "script-src 'self' 'nonce-#{nonce}' https://www.googletagmanager.com; " <>
          "style-src 'self'; " <>
          "img-src 'self' data: https://www.google-analytics.com https://www.googletagmanager.com; " <>
          "connect-src 'self' https://www.google-analytics.com https://analytics.google.com https://www.googletagmanager.com;"
    })
  end

  # Other scopes may use custom stacks.
  # scope "/api", HighSocietyWeb do
  #   pipe_through :api
  # end

  import Phoenix.LiveDashboard.Router

  # Also mounted in production (see the /admin scope below) - this
  # unauthenticated /dev copy is dev-only convenience, not the one to rely
  # on for prod traffic monitoring.
  if Application.compile_env(:high_society, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HighSocietyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", HighSocietyWeb do
    pipe_through [:browser, :require_authenticated_user]

    # `/tournament` (registration) is deliberately its own live_session,
    # separate from the one below - see `HighSocietyWeb.TournamentGeoCheck`
    # for why the geo-restriction it adds has to be scoped this way rather
    # than shared across every authenticated page.
    live_session :tournament_registration,
      on_mount: [
        {HighSocietyWeb.UserAuth, :require_authenticated},
        {HighSocietyWeb.TournamentGeoCheck, :restrict_registration}
      ] do
      live "/tournament", TournamentLive, :new
      # 3 segments, matching the shape of the routes below (never
      # `/tournament/:id`, a bare 2-segment dynamic route - that would be
      # declared earlier in this file than the also-2-segment, but
      # static, `/tournament/rules` below, and a dynamic segment
      # declared first wins the match in Phoenix's router regardless of
      # which one is "more specific" - confirmed the hard way).
      live "/tournament/:id/register", TournamentLive, :edit
    end

    live_session :require_authenticated_user,
      on_mount: [{HighSocietyWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/badges", BadgesLive, :index
      live "/tournament/:id/tables", GameLive.TournamentTables, :index
      live "/tournament/:id/tables/:slug", GameLive.TournamentTable, :show
      live "/tournament/:id/results", GameLive.TournamentResults, :show
      live "/games/war", GameLive.War, :show
      live "/games/blackjack", GameLive.Blackjack, :show
      live "/games/blackjack/leaderboard", GameLive.Leaderboard, :blackjack
      live "/games/poker", GameLive.PokerLobby, :index
      live "/games/poker/leaderboard", GameLive.Leaderboard, :poker
      live "/games/poker/:slug", GameLive.PokerTable, :show
      live "/games/battleship", GameLive.Battleship, :show
      live "/games/battleship/lobby", GameLive.BattleshipLobby, :index
      live "/games/battleship/lobby/:slug", GameLive.BattleshipMatch, :show
      live "/games/slots", GameLive.Slots, :show
      live "/games/roulette", GameLive.Roulette, :show
      live "/games/zombie-attack", GameLive.ZombieAttack, :show
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/admin", HighSocietyWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/token-transactions/export", AdminTokenTransactionsController, :export

    # Same LiveDashboard mounted at /dev/dashboard in dev, but reachable in
    # every environment (including prod) and gated by admin auth instead of
    # `dev_routes` - the whole point is watching real Postgres/BEAM stats
    # (including the ecto_psql_extras-powered "Ecto Stats" page) during
    # actual production traffic, not just locally. `live_dashboard/2` builds
    # its own internal `live_session`, so it can't be nested inside the one
    # below - it needs the full on_mount chain (`:require_admin` alone
    # assumes `current_scope` is already set, same as everywhere else this
    # pair is used - see `HighSocietyWeb.UserAuth.on_mount/4`).
    live_dashboard "/dashboard",
      metrics: HighSocietyWeb.Telemetry,
      live_session_name: :admin_live_dashboard,
      on_mount: [
        {HighSocietyWeb.UserAuth, :require_authenticated},
        {HighSocietyWeb.UserAuth, :require_admin}
      ]

    live_session :require_admin,
      on_mount: [
        {HighSocietyWeb.UserAuth, :require_authenticated},
        {HighSocietyWeb.UserAuth, :require_admin}
      ] do
      live "/token-transactions", AdminLive.TokenTransactions, :index
      live "/tournaments", AdminLive.Tournaments, :index
    end
  end

  scope "/", HighSocietyWeb do
    pipe_through [:browser]
    get "/health", HealthcheckController, :status

    live_session :current_user,
      on_mount: [{HighSocietyWeb.UserAuth, :mount_current_scope}] do
      live "/", DashboardLive, :index
      live "/tokens", TokensLive, :index
      live "/support", SupportLive, :new
      live "/terms", LegalLive, :terms
      live "/privacy", LegalLive, :privacy
      live "/cookies", LegalLive, :cookies
      live "/responsible-gaming", LegalLive, :responsible_gaming
      live "/age-restriction", LegalLive, :age_restriction
      live "/tournament/rules", LegalLive, :tournament_rules
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/webhooks", HighSocietyWeb do
    pipe_through :api

    post "/resend/inbound", ResendWebhookController, :create
  end
end
