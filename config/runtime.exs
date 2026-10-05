import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL is missing. Set it to the production PostgreSQL connection URL."

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE is missing. Generate one with: mix phx.gen.secret"

  webhook_signing_secret =
    System.get_env("IRONHOLD_WEBHOOK_SIGNING_SECRET") ||
      raise "IRONHOLD_WEBHOOK_SIGNING_SECRET is missing. Set the production webhook signing secret."

  if byte_size(webhook_signing_secret) < 32 do
    raise "IRONHOLD_WEBHOOK_SIGNING_SECRET must be at least 32 bytes."
  end

  host = System.get_env("PHX_HOST", "example.com")
  port = String.to_integer(System.get_env("PORT", "4000"))
  pool_size = String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :ironhold, Ironhold.Repo,
    url: database_url,
    pool_size: pool_size

  config :ironhold, :webhook_signing_secret, webhook_signing_secret

  config :ironhold, IronholdWeb.Endpoint,
    server: true,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
