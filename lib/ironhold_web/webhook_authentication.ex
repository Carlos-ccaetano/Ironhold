defmodule IronholdWeb.WebhookAuthentication do
  @moduledoc """
  Renders the public response for webhook authentication failures.
  """

  import Plug.Conn

  @invalid_signature_message "valid webhook signature required"

  @doc """
  Sends the generic webhook authentication failure and halts the connection.
  """
  @spec reject(Plug.Conn.t()) :: Plug.Conn.t()
  def reject(conn) do
    body =
      Phoenix.json_library().encode!(%{
        errors: [%{detail: @invalid_signature_message}]
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, body)
    |> halt()
  end
end
