import Config

database_config =
  case System.get_env("DATABASE_URL") do
    nil ->
      [
        username: System.get_env("POSTGRES_USER", "postgres"),
        password: System.get_env("POSTGRES_PASSWORD", "postgres"),
        hostname: System.get_env("POSTGRES_HOST", "localhost"),
        database: "ironhold_test#{System.get_env("MIX_TEST_PARTITION")}"
      ]

    url ->
      [url: url]
  end

config :ironhold,
       Ironhold.Repo,
       Keyword.merge(database_config,
         pool: Ecto.Adapters.SQL.Sandbox,
         pool_size: System.schedulers_online() * 2
       )

config :ironhold, IronholdWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("test-only-", 8),
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
