defmodule IronholdWeb.WebhookControllerTest do
  use IronholdWeb.ConnCase, async: true

  @valid_webhook %{
    id: "evt_123",
    type: "order.created",
    data: %{
      order_id: "123",
      status: "created"
    }
  }

  test "POST /api/webhooks accepts and stores a valid webhook", %{conn: conn} do
    conn =
      conn
      |> accept_json()
      |> post(~p"/api/webhooks", @valid_webhook)

    assert json_response(conn, 202) == %{
             "data" => %{
               "event_id" => "evt_123",
               "status" => "accepted"
             }
           }
  end

  test "POST /api/webhooks requires an id", %{conn: conn} do
    webhook = Map.delete(@valid_webhook, :id)

    conn =
      conn
      |> accept_json()
      |> post(~p"/api/webhooks", webhook)

    assert invalid_webhook_response(conn)
  end

  test "POST /api/webhooks requires a non-empty string type", %{conn: conn} do
    conn =
      conn
      |> accept_json()
      |> post(~p"/api/webhooks", %{@valid_webhook | type: "   "})

    assert invalid_webhook_response(conn)
  end

  test "POST /api/webhooks requires data to be a JSON object", %{conn: conn} do
    conn =
      conn
      |> accept_json()
      |> post(~p"/api/webhooks", %{@valid_webhook | data: ["not", "an", "object"]})

    assert invalid_webhook_response(conn)
  end

  test "POST /api/webhooks rejects a duplicate event id", %{conn: conn} do
    conn =
      conn
      |> accept_json()
      |> post(~p"/api/webhooks", @valid_webhook)

    duplicate_conn =
      conn
      |> recycle()
      |> accept_json()
      |> post(~p"/api/webhooks", @valid_webhook)

    assert json_response(duplicate_conn, 409) == %{
             "errors" => [
               %{"detail" => "a webhook with this id has already been received"}
             ]
           }
  end

  test "the webhook route uses the API pipeline" do
    assert %{
             pipe_through: [:api],
             plug: IronholdWeb.WebhookController,
             plug_opts: :create
           } =
             Phoenix.Router.route_info(
               IronholdWeb.Router,
               "POST",
               "/api/webhooks",
               "localhost"
             )
  end

  defp accept_json(conn), do: put_req_header(conn, "accept", "application/json")

  defp invalid_webhook_response(conn) do
    assert json_response(conn, 422) == %{
             "errors" => [
               %{
                 "detail" => "id, type, and data must be provided in the expected format"
               }
             ]
           }
  end
end
