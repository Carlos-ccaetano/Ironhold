defmodule IronholdWeb.Plugs.RequireMatchingWebhookIdTest do
  use Ironhold.DataCase, async: true

  import Plug.Conn
  import Plug.Test

  alias Ironhold.Repo
  alias Ironhold.Webhooks.ReceivedWebhook
  alias IronholdWeb.Plugs.RequireMatchingWebhookId

  @authenticated_id_private_key :ironhold_authenticated_webhook_id
  @invalid_signature_response ~s({"errors":[{"detail":"valid webhook signature required"}]})
  @opts RequireMatchingWebhookId.init([])

  test "continues with the unchanged connection when IDs match" do
    conn = matching_conn("evt_test_123", %{"id" => "evt_test_123"})

    assert RequireMatchingWebhookId.call(conn, @opts) == conn
  end

  test "rejects different IDs" do
    conn = matching_conn("evt_header", %{"id" => "evt_body"})

    assert_authentication_failure(conn)
  end

  test "compares IDs case-sensitively" do
    conn = matching_conn("evt_test_123", %{"id" => "EVT_TEST_123"})

    assert_authentication_failure(conn)
  end

  test "does not trim IDs before comparison" do
    conn = matching_conn("evt_test_123", %{"id" => "evt_test_123 "})

    assert_authentication_failure(conn)
  end

  test "fails closed when the authenticated ID is absent" do
    conn = body_params_conn(%{"id" => "evt_test_123"})

    assert_authentication_failure(conn)
  end

  test "fails closed when the body ID is absent" do
    conn = matching_conn("evt_test_123", %{"type" => "test.ping"})

    assert_authentication_failure(conn)
  end

  test "rejects unexpected ID and body parameter formats" do
    connections = [
      matching_conn(123, %{"id" => "123"}),
      matching_conn("evt_test_123", %{"id" => 123}),
      matching_conn("evt_test_123", %{"id" => ["evt_test_123"]}),
      authenticated_conn("evt_test_123")
    ]

    Enum.each(connections, &assert_authentication_failure/1)
  end

  test "uses the generic webhook authentication response" do
    returned_conn =
      "evt_header"
      |> matching_conn(%{"id" => "evt_body"})
      |> RequireMatchingWebhookId.call(@opts)

    assert returned_conn.status == 401
    assert returned_conn.resp_body == @invalid_signature_response
    assert get_resp_header(returned_conn, "content-type") == ["application/json; charset=utf-8"]
  end

  test "halts the connection after a mismatch" do
    returned_conn =
      "evt_header"
      |> matching_conn(%{"id" => "evt_body"})
      |> RequireMatchingWebhookId.call(@opts)

    assert returned_conn.halted
  end

  test "does not persist or produce domain side effects" do
    initial_count = Repo.aggregate(ReceivedWebhook, :count)

    matching_conn("evt_test_123", %{"id" => "evt_test_123"})
    |> RequireMatchingWebhookId.call(@opts)

    matching_conn("evt_header", %{"id" => "evt_body"})
    |> RequireMatchingWebhookId.call(@opts)

    assert Repo.aggregate(ReceivedWebhook, :count) == initial_count
  end

  defp matching_conn(authenticated_id, body_params) do
    authenticated_id
    |> authenticated_conn()
    |> Map.put(:body_params, body_params)
  end

  defp authenticated_conn(authenticated_id) do
    :post
    |> conn("/api/webhooks")
    |> put_private(@authenticated_id_private_key, authenticated_id)
  end

  defp body_params_conn(body_params) do
    :post
    |> conn("/api/webhooks")
    |> Map.put(:body_params, body_params)
  end

  defp assert_authentication_failure(conn) do
    returned_conn = RequireMatchingWebhookId.call(conn, @opts)

    assert returned_conn.halted
    assert returned_conn.status == 401
    assert returned_conn.resp_body == @invalid_signature_response
  end
end
