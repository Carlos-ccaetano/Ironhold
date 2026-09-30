defmodule IronholdWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ironhold

  @session_options [
    store: :cookie,
    key: "_ironhold_key",
    signing_salt: "ironhold-session",
    same_site: "Lax"
  ]

  plug Plug.Static,
    at: "/",
    from: :ironhold,
    gzip: false,
    only: IronholdWeb.static_paths()

  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :ironhold
  end

  plug Plug.RequestId
  plug IronholdWeb.Plugs.RequireJsonContentType
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, {:json, length: 262_144}],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug IronholdWeb.Router
end
