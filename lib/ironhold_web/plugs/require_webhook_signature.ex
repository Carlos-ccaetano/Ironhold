defmodule IronholdWeb.Plugs.RequireWebhookSignature do
  @moduledoc """
  Authenticates the raw body of Tidewake webhook ingestion requests.
  """

  import Plug.Conn

  alias Ironhold.Ingestion.Signature
  alias IronholdWeb.ErrorJSON
  alias IronholdWeb.WebhookAuthentication

  @behaviour Plug

  @maximum_body_size 262_144
  @authenticated_body_private_key :ironhold_authenticated_webhook_body
  @authenticated_id_private_key :ironhold_authenticated_webhook_id
  @required_headers ["tidewake-id", "tidewake-timestamp", "tidewake-signature"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{method: "POST", path_info: ["api", "webhooks"]} = conn, _opts) do
    with {:ok, [header_id, timestamp, signature]} <- required_headers(conn),
         {:ok, body, conn} <- read_bounded_body(conn),
         {:ok, secret} <- Application.fetch_env(:ironhold, :webhook_signing_secret),
         {:ok, verified_id} <-
           Signature.verify(
             header_id,
             timestamp,
             signature,
             body,
             secret,
             System.system_time(:second)
           ) do
      conn
      |> put_private(@authenticated_body_private_key, body)
      |> put_private(@authenticated_id_private_key, verified_id)
    else
      {:error, :payload_too_large, conn} -> payload_too_large(conn)
      _authentication_failure -> WebhookAuthentication.reject(conn)
    end
  end

  def call(conn, _opts), do: conn

  defp required_headers(conn) do
    @required_headers
    |> Enum.reduce_while({:ok, []}, fn header, {:ok, values} ->
      case single_header(conn, header) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end
  end

  defp single_header(conn, header) do
    with [value] <- get_req_header(conn, header),
         :nomatch <- :binary.match(value, ",") do
      {:ok, value}
    else
      _missing_duplicated_or_combined -> :error
    end
  end

  defp read_bounded_body(conn) do
    case Plug.Conn.read_body(conn, length: @maximum_body_size) do
      {:ok, body, conn} -> {:ok, body, conn}
      {:more, _partial_body, conn} -> {:error, :payload_too_large, conn}
      {:error, _reason} -> :error
    end
  end

  defp payload_too_large(conn) do
    body =
      "413.json"
      |> ErrorJSON.render(%{})
      |> Phoenix.json_library().encode!()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(413, body)
    |> halt()
  end
end
