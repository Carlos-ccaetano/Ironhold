import Config

config :logger, level: :info

config :ironhold, IronholdWeb.Endpoint, force_ssl: [rewrite_on: [:x_forwarded_proto], hsts: true]
