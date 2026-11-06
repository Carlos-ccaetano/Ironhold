import Config

config :ironhold,
  ecto_repos: [Ironhold.Repo]

config :ironhold, Ironhold.Webhooks.ReplayCleanup, interval: :timer.minutes(5)

config :ironhold, IronholdWeb.Endpoint,
  url: [host: "localhost"],
  adapter: IronholdWeb.HTTPAdapter,
  render_errors: [
    formats: [html: IronholdWeb.ErrorHTML, json: IronholdWeb.ErrorJSON],
    layout: false
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: []

# Generic request/SQL loggers can format bodies, parameter keys and exceptions.
# MetricEvents retains timings without forwarding their raw metadata.
config :phoenix, :logger, false
config :ironhold, Ironhold.Repo, log: false
config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
