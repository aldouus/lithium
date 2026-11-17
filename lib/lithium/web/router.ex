defmodule Lithium.Web.Router do
  use Phoenix.Router

  import Phoenix.Controller
  import Plug.Conn

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(Lithium.Web.Pipeline)
  end

  pipeline :authenticated do
    plug(Guardian.Plug.EnsureAuthenticated)
  end

  scope "/", Lithium.Web do
    pipe_through(:browser)

    get("/", SessionController, :home)
    post("/login", SessionController, :create)
    get("/login/verify", SessionController, :verify)
    post("/logout", SessionController, :delete)
  end

  scope "/", Lithium.Web do
    pipe_through([:browser, :authenticated])

    get("/spotify", SpotifyController, :connect)
    get("/spotify/callback", SpotifyController, :callback)
  end
end
