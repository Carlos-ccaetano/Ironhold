defmodule IronholdWeb.WebhookBodyReader do
  @moduledoc """
  Reuses an authenticated webhook body when `Plug.Parsers` reads the request.

  Authentication stores the exact bytes in `conn.private` under
  `:ironhold_authenticated_webhook_body`. This reader returns those bytes once
  and records consumption under `:ironhold_authenticated_webhook_body_consumed`.
  Other requests continue through `Plug.Conn.read_body/2` unchanged.
  """

  @authenticated_body_private_key :ironhold_authenticated_webhook_body
  @body_consumed_private_key :ironhold_authenticated_webhook_body_consumed

  @doc """
  Reads a request body for `Plug.Parsers`.

  An authenticated body preserved in `conn.private` is returned at most once.
  """
  @spec read_body(Plug.Conn.t(), Keyword.t()) ::
          {:ok, binary(), Plug.Conn.t()}
          | {:more, binary(), Plug.Conn.t()}
          | {:error, term()}
  def read_body(conn, opts) do
    case conn.private do
      %{
        @authenticated_body_private_key => body,
        @body_consumed_private_key => true
      }
      when is_binary(body) ->
        Plug.Conn.read_body(conn, opts)

      %{@authenticated_body_private_key => body} when is_binary(body) ->
        conn = Plug.Conn.put_private(conn, @body_consumed_private_key, true)
        {:ok, body, conn}

      _private ->
        Plug.Conn.read_body(conn, opts)
    end
  end
end
