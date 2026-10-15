defmodule IronholdWeb.Plugs.RequireMatchingWebhookIdTest do
  use Ironhold.DataCase, async: true

  import Plug.Conn
  import Plug.Test

  alias Ironhold.Repo
  alias Ironhold.Webhooks.{ReceivedWebhook, ReplayFingerprint}
  alias IronholdWeb.Plugs.RequireMatchingWebhookId

  @authenticated_body_private_key :ironhold_authenticated_webhook_body
  @authenticated_body_consumed_private_key :ironhold_authenticated_webhook_body_consumed
  @authenticated_id_private_key :ironhold_authenticated_webhook_id
  @authenticated_signed_at_private_key :ironhold_authenticated_webhook_signed_at
  @identifier_mismatch_event [:ironhold, :webhooks, :authentication, :identifier_mismatch]
  @invalid_signature_response ~s({"errors":[{"detail":"valid webhook signature required"}]})
  @opts RequireMatchingWebhookId.init([])
  @replay_metadata_private_key :ironhold_authenticated_webhook_replay
  @signed_at 1_700_000_000
  @validated_signature "v1=" <> String.duplicate("a", 64)

  test "attaches safe replay metadata only after IDs match" do
    attach_identifier_mismatch_event()
    conn = matching_conn("evt_test_123", %{"id" => "evt_test_123"})

    returned_conn = RequireMatchingWebhookId.call(conn, @opts)

    assert returned_conn.private[@replay_metadata_private_key] == %{
             fingerprint: ReplayFingerprint.derive(@validated_signature),
             expires_at: ~U[2023-11-14 22:18:20Z]
           }

    refute Map.has_key?(returned_conn.private, @authenticated_body_private_key)
    refute Map.has_key?(returned_conn.private, @authenticated_body_consumed_private_key)
    refute Map.has_key?(returned_conn.private, @authenticated_signed_at_private_key)
    refute_receive {:identifier_mismatch_event, _, _}
  end

  test "rejects different IDs and emits one bounded mismatch event" do
    attach_identifier_mismatch_event()
    conn = matching_conn("evt_header", %{"id" => "evt_body"})

    assert_authentication_failure(conn)
    assert_receive {:identifier_mismatch_event, %{count: 1}, %{}}
    refute_receive {:identifier_mismatch_event, _, _}
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
    |> put_req_header("tidewake-signature", @validated_signature)
    |> put_private(@authenticated_body_private_key, "authenticated body")
    |> put_private(@authenticated_body_consumed_private_key, true)
    |> put_private(@authenticated_id_private_key, authenticated_id)
    |> put_private(@authenticated_signed_at_private_key, @signed_at)
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
    refute Map.has_key?(returned_conn.private, @replay_metadata_private_key)
    refute Map.has_key?(returned_conn.private, @authenticated_body_private_key)
    refute Map.has_key?(returned_conn.private, @authenticated_signed_at_private_key)
  end

  defp attach_identifier_mismatch_event do
    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @identifier_mismatch_event,
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:identifier_mismatch_event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
