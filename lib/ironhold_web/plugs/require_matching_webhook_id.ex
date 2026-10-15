defmodule IronholdWeb.Plugs.RequireMatchingWebhookId do
  @moduledoc """
  Requires the authenticated webhook ID to match the decoded body ID.
  """

  alias Ironhold.Ingestion.Signature
  alias Ironhold.Webhooks.ReplayFingerprint
  alias IronholdWeb.{Telemetry, WebhookAuthentication}

  @behaviour Plug

  @authenticated_body_private_key :ironhold_authenticated_webhook_body
  @authenticated_body_consumed_private_key :ironhold_authenticated_webhook_body_consumed
  @authenticated_id_private_key :ironhold_authenticated_webhook_id
  @authenticated_signed_at_private_key :ironhold_authenticated_webhook_signed_at
  @replay_metadata_private_key :ironhold_authenticated_webhook_replay

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
    attach_replay_metadata(conn)
  end

  def call(conn, _opts) do
    reject(conn)
  end

  defp attach_replay_metadata(conn) do
    with %{@authenticated_signed_at_private_key => signed_at} <- conn.private,
         [validated_signature] <- Plug.Conn.get_req_header(conn, "tidewake-signature"),
         {:ok, expires_at} <- Signature.acceptance_expires_at(signed_at) do
      replay_metadata = %{
        fingerprint: ReplayFingerprint.derive(validated_signature),
        expires_at: expires_at
      }

      conn
      |> clear_transient_authentication_data()
      |> Plug.Conn.put_private(@replay_metadata_private_key, replay_metadata)
    else
      _missing_authenticated_value -> reject(conn)
    end
  end

  defp reject(conn) do
    Telemetry.emit_authentication_identifier_mismatch()

    conn
    |> clear_transient_authentication_data()
    |> WebhookAuthentication.reject()
  end

  defp clear_transient_authentication_data(conn) do
    private =
      conn.private
      |> Map.delete(@authenticated_body_private_key)
      |> Map.delete(@authenticated_body_consumed_private_key)
      |> Map.delete(@authenticated_signed_at_private_key)

    %{conn | private: private}
  end
end
