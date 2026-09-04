defmodule HighSocietyWeb.Router do
  use HighSocietyWeb, :router

  import HighSocietyWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
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
  # per-request nonce since `script-src` has no 'unsafe-inline'.
  defp put_csp_headers(conn, _opts) do
    nonce = Base.encode64(:crypto.strong_rand_bytes(16))

    conn
    |> assign(:csp_nonce, nonce)
    |> put_secure_browser_headers(%{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'nonce-#{nonce}'; style-src 'self'; img-src 'self' data:;"
    })
  end

  # Other scopes may use custom stacks.
  # scope "/api", HighSocietyWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:high_society, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HighSocietyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", HighSocietyWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{HighSocietyWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/badges", BadgesLive, :index
      live "/games/war", GameLive.War, :show
      live "/games/blackjack", GameLive.Blackjack, :show
      live "/games/poker", GameLive.PokerLobby, :index
      live "/games/poker/:slug", GameLive.PokerTable, :show
      live "/games/battleship", GameLive.Battleship, :show
      live "/games/battleship/lobby", GameLive.BattleshipLobby, :index
      live "/games/battleship/lobby/:slug", GameLive.BattleshipMatch, :show
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", HighSocietyWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{HighSocietyWeb.UserAuth, :mount_current_scope}] do
      live "/", DashboardLive, :index
      live "/support", SupportLive, :new
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
