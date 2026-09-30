defmodule IronholdWeb.WebhookController do
  use IronholdWeb, :controller

  alias Ironhold.Webhooks
  alias IronholdWeb.Telemetry

  @invalid_webhook_message "id, type, and data must be provided in the expected format"
  @duplicate_webhook_message "a webhook with this id has already been received"

  def create(conn, params) do
    with {:ok, attrs} <- webhook_attrs(params),
         {:ok, webhook} <- Webhooks.receive_webhook(attrs) do
      Telemetry.emit_ingestion_accepted()

      conn
      |> put_status(:accepted)
      |> json(%{
        data: %{
          event_id: webhook.event_id,
          status: "accepted"
        }
      })
    else
      {:error, :duplicate_event_id} ->
        rejection_response(
          conn,
          :conflict,
          @duplicate_webhook_message,
          :duplicate_event_id
        )

      {:error, %Ecto.Changeset{}} ->
        rejection_response(conn, :unprocessable_entity, @invalid_webhook_message, :validation)

      {:error, :invalid_webhook} ->
        rejection_response(conn, :unprocessable_entity, @invalid_webhook_message, :validation)
    end
  end

  defp webhook_attrs(%{"id" => id, "type" => type, "data" => data}) do
    if non_empty_string?(id) and non_empty_string?(type) and is_map(data) do
      {:ok, %{event_id: id, event_type: type, payload: data}}
    else
      {:error, :invalid_webhook}
    end
  end

  defp webhook_attrs(_params), do: {:error, :invalid_webhook}

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp rejection_response(conn, status, detail, reason) do
    Telemetry.emit_ingestion_rejected(reason)

    conn
    |> put_status(status)
    |> json(%{errors: [%{detail: detail}]})
  end
end
