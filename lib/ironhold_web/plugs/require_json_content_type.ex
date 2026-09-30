defmodule IronholdWeb.Plugs.RequireJsonContentType do
  @moduledoc """
  Requires API requests with bodies to declare a single JSON content type.
  """

  import Plug.Conn

  alias Plug.Conn.Utils

  @behaviour Plug

  @body_methods ~w(POST PUT PATCH DELETE)
  @unsupported_media_type_message "content type must be application/json"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{method: method, path_info: ["api" | _]} = conn, _opts)
      when method in @body_methods do
    case get_req_header(conn, "content-type") do
      [content_type] -> validate_content_type(conn, content_type)
      _headers -> reject(conn)
    end
  end

  def call(conn, _opts), do: conn

  defp validate_content_type(conn, content_type) do
    case Utils.content_type(content_type) do
      {:ok, "application", "json", _params} -> conn
      _invalid_or_unsupported -> reject(conn)
    end
  end

  defp reject(conn) do
    body =
      Phoenix.json_library().encode!(%{
        errors: [%{detail: @unsupported_media_type_message}]
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(415, body)
    |> halt()
  end
end
