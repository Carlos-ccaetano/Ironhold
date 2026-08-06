import Config

database_config =
  case System.get_env("DATABASE_URL") do
    nil ->
      [
        username: System.get_env("POSTGRES_USER", "postgres"),
        password: System.get_env("POSTGRES_PASSWORD", "postgres"),
        hostname: System.get_env("POSTGRES_HOST", "localhost"),
        database: System.get_env("POSTGRES_DB", "ironhold_dev")
      ]

    url ->
      [url: url]
  end

config :ironhold, Ironhold.Repo, database_config

config :ironhold, IronholdWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: String.duplicate("development-only-", 4),
  watchers: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
