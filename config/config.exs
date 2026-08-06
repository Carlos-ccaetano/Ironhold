import Config

config :ironhold,
  ecto_repos: [Ironhold.Repo]

config :ironhold, IronholdWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: IronholdWeb.ErrorHTML, json: IronholdWeb.ErrorJSON],
    layout: false
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
