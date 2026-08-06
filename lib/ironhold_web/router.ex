defmodule IronholdWeb.Router do
  use IronholdWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {IronholdWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'"
    }
  end

  scope "/", IronholdWeb do
    pipe_through :browser

    get "/", PageController, :home
  end
end
