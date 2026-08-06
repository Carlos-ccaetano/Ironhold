defmodule Ironhold.Repo do
  use Ecto.Repo,
    otp_app: :ironhold,
    adapter: Ecto.Adapters.Postgres
end
