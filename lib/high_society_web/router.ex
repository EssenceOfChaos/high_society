defmodule HighSocietyWeb.Router do
  use HighSocietyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug HighSocietyWeb.Plugs.SetUser

  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HighSocietyWeb do
    pipe_through :browser # Use the default browser stack

    get "/", PageController, :index
    scope "/posts" do
      post "/:id/upvote", PostController, :upvote
      post "/:id/downvote", PostController, :downvote
    end
    
    resources "/users", UserController, only: [:show, :new, :create]
    resources "/posts", PostController
   
        ## Routes for sessions ##
  get    "/login",  SessionController, :new
  post   "/login",  SessionController, :create
  delete "/logout", SessionController, :delete

  end

  # Other scopes may use custom stacks.
  # scope "/api", HighSocietyWeb do
  #   pipe_through :api
  # end
end
