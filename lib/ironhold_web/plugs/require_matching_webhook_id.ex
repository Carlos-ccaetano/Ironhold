defmodule IronholdWeb.Plugs.RequireMatchingWebhookId do
  @moduledoc """
  Requires the authenticated webhook ID to match the decoded body ID.
  """

  alias IronholdWeb.{Telemetry, WebhookAuthentication}

  @behaviour Plug

  @authenticated_id_private_key :ironhold_authenticated_webhook_id

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(
        %Plug.Conn{
          private: %{@authenticated_id_private_key => authenticated_id},
          body_params: %{"id" => body_id}
        } = conn,
        _opts
      )
      when is_binary(authenticated_id) and is_binary(body_id) and
             authenticated_id == body_id do
    conn
  end

  def call(conn, _opts) do
    Telemetry.emit_authentication_identifier_mismatch()
    WebhookAuthentication.reject(conn)
  end
end
