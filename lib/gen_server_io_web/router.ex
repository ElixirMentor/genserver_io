defmodule GenServerIoWeb.Router do
  use GenServerIoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GenServerIoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GenServerIoWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Alias game routes
    live "/alias", AliasLive
    live "/alias/:session_id", AliasLive

    # Anagrams game routes
    live "/anagrams", AnagramsLive
    live "/anagrams/:session_id", AnagramsLive

    # Truth or Lie game routes
    live "/truth_or_lie", TruthOrLieLive
    live "/truth_or_lie/:session_id", TruthOrLieLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", GenServerIoWeb do
  #   pipe_through :api
  # end
end
