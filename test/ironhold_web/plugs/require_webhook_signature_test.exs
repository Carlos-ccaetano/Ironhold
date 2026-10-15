defmodule IronholdWeb.Plugs.RequireWebhookSignatureTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias IronholdWeb.Plugs.RequireWebhookSignature

  @secret "tidewake_test_secret_not_for_production"
  @authenticated_body_private_key :ironhold_authenticated_webhook_body
  @authenticated_id_private_key :ironhold_authenticated_webhook_id
  @authenticated_signed_at_private_key :ironhold_authenticated_webhook_signed_at
  @replay_metadata_private_key :ironhold_authenticated_webhook_replay
  @verified_event [:ironhold, :webhooks, :authentication, :verified]
  @rejected_event [:ironhold, :webhooks, :authentication, :rejected]
  @invalid_signature_response ~s({"errors":[{"detail":"valid webhook signature required"}]})
  @payload_too_large_response ~s({"errors":[{"detail":"request body exceeds the 262144-byte limit"}]})
  @opts RequireWebhookSignature.init([])

  setup do
    previous_secret = Application.fetch_env(:ironhold, :webhook_signing_secret)
    Application.put_env(:ironhold, :webhook_signing_secret, @secret)

    on_exit(fn -> restore_secret(previous_secret) end)
  end

  test "ignores unrelated methods and paths without reading their body" do
    attach_authentication_events()

    requests = [
      {:post, "/api/other", "unrelated path body"},
      {:put, "/api/webhooks", "unrelated method body"}
    ]

    Enum.each(requests, fn {method, path, body} ->
      conn = conn(method, path, body)

      assert RequireWebhookSignature.call(conn, @opts) == conn
      assert {:ok, ^body, _conn} = Plug.Conn.read_body(conn)
    end)

    refute_receive {:authentication_event, _, _, _}
  end

  test "emits one verified event with bounded data after successful authentication" do
    attach_authentication_events()
    body = ~s({"data":{"ok":true},"id":"evt_test_123","type":"test.ping"})
    conn = signed_conn(body)

    refute RequireWebhookSignature.call(conn, @opts).halted

    assert_receive {:authentication_event, @verified_event, %{count: 1}, %{}}
    refute_receive {:authentication_event, _, _, _}
  end

  test "rejects a missing signing header" do
    conn = signed_conn("{}") |> delete_req_header("tidewake-id")

    assert_authentication_failure(conn)
  end

  test "rejects a duplicated signing header" do
    conn =
      "{}"
      |> signed_conn()
      |> prepend_req_headers([{"tidewake-id", "evt_duplicate"}])

    assert_authentication_failure(conn)
  end

  test "rejects an ambiguous combined signing header" do
    conn = signed_conn("{}") |> put_req_header("tidewake-id", "evt_test_123,evt_other")

    assert_authentication_failure(conn)
  end

  test "emits one rejected event with bounded data for an invalid signature" do
    attach_authentication_events()
    conn = signed_conn("{}", signature: "v1=" <> String.duplicate("0", 64))

    assert_authentication_failure(conn)

    assert_receive {:authentication_event, @rejected_event, %{count: 1}, %{}}
    refute_receive {:authentication_event, _, _, _}
  end

  test "rejects an invalid timestamp" do
    conn = signed_conn("{}", timestamp: "not-a-timestamp")

    assert_authentication_failure(conn)
  end

  test "rejects a body changed after signing" do
    timestamp = current_timestamp()
    signature = signature("evt_test_123", timestamp, ~s({"ok":true}), @secret)

    conn =
      signed_conn(~s({"ok":false}),
        timestamp: timestamp,
        signature: signature
      )

    assert_authentication_failure(conn)
  end

  test "preserves the existing response for an oversized body" do
    attach_authentication_events()
    body = String.duplicate("x", 262_145)
    conn = signed_conn(body)

    returned_conn = RequireWebhookSignature.call(conn, @opts)

    assert returned_conn.halted
    assert returned_conn.status == 413
    assert returned_conn.resp_body == @payload_too_large_response
    assert_receive {:authentication_event, @rejected_event, %{count: 1}, %{}}
    refute_receive {:authentication_event, _, _, _}
  end

  test "accepts a body at the exact size limit" do
    body = String.duplicate("x", 262_144)
    conn = signed_conn(body)

    returned_conn = RequireWebhookSignature.call(conn, @opts)

    refute returned_conn.halted
    assert returned_conn.private[@authenticated_body_private_key] === body
  end

  test "fails closed when the configured secret is absent" do
    Application.delete_env(:ironhold, :webhook_signing_secret)

    assert_authentication_failure(signed_conn("{}"))
  end

  test "preserves only the transient values needed for final authentication" do
    body = "{\r\n  \"type\": \"test.ping\", \"id\": \"evt_test_123\", \"data\": {}\n}"
    timestamp = current_timestamp()
    conn = signed_conn(body, timestamp: timestamp)

    returned_conn = RequireWebhookSignature.call(conn, @opts)

    assert returned_conn.private[@authenticated_body_private_key] === body
    assert returned_conn.private[@authenticated_id_private_key] == "evt_test_123"

    assert returned_conn.private[@authenticated_signed_at_private_key] ==
             String.to_integer(timestamp)

    refute Map.has_key?(returned_conn.private, @replay_metadata_private_key)
  end

  test "uses the same generic response for different authentication failures" do
    missing_header = signed_conn("{}") |> delete_req_header("tidewake-id")
    invalid_signature = signed_conn("{}", signature: "v1=" <> String.duplicate("f", 64))

    missing_header_response = RequireWebhookSignature.call(missing_header, @opts)
    invalid_signature_response = RequireWebhookSignature.call(invalid_signature, @opts)

    assert response_identity(missing_header_response) ==
             response_identity(invalid_signature_response)

    assert missing_header_response.resp_body == @invalid_signature_response
  end

  test "does not expose the secret, signature, or body in an error response" do
    secret = "sensitive-secret-value-with-at-least-32-bytes"
    body = ~s({"private":"sensitive-body-value"})
    presented_signature = "v1=" <> String.duplicate("a", 64)
    Application.put_env(:ironhold, :webhook_signing_secret, secret)

    returned_conn =
      body
      |> signed_conn(signature: presented_signature)
      |> RequireWebhookSignature.call(@opts)

    assert returned_conn.resp_body == @invalid_signature_response
    refute String.contains?(returned_conn.resp_body, secret)
    refute String.contains?(returned_conn.resp_body, presented_signature)
    refute String.contains?(returned_conn.resp_body, body)
  end

  defp signed_conn(body, overrides \\ []) do
    header_id = Keyword.get(overrides, :header_id, "evt_test_123")
    timestamp = Keyword.get(overrides, :timestamp, current_timestamp())
    secret = Application.get_env(:ironhold, :webhook_signing_secret, @secret)

    signature =
      Keyword.get_lazy(overrides, :signature, fn ->
        signature(header_id, timestamp, body, secret)
      end)

    :post
    |> conn("/api/webhooks", body)
    |> put_req_header("tidewake-id", header_id)
    |> put_req_header("tidewake-timestamp", timestamp)
    |> put_req_header("tidewake-signature", signature)
  end

  defp signature(header_id, timestamp, body, secret) do
    ["v1.", header_id, ".", timestamp, ".", body]
    |> IO.iodata_to_binary()
    |> then(&:crypto.mac(:hmac, :sha256, secret, &1))
    |> Base.encode16(case: :lower)
    |> then(&("v1=" <> &1))
  end

  defp current_timestamp, do: System.system_time(:second) |> Integer.to_string()

  defp assert_authentication_failure(conn) do
    returned_conn = RequireWebhookSignature.call(conn, @opts)

    assert returned_conn.halted
    assert returned_conn.status == 401
    assert returned_conn.resp_body == @invalid_signature_response
    assert get_resp_header(returned_conn, "content-type") == ["application/json; charset=utf-8"]
    refute Map.has_key?(returned_conn.private, @authenticated_signed_at_private_key)
    refute Map.has_key?(returned_conn.private, @replay_metadata_private_key)
  end

  defp response_identity(conn) do
    {conn.status, get_resp_header(conn, "content-type"), conn.resp_body, conn.halted}
  end

  defp attach_authentication_events do
    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [@verified_event, @rejected_event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:authentication_event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp restore_secret({:ok, secret}),
    do: Application.put_env(:ironhold, :webhook_signing_secret, secret)

  defp restore_secret(:error), do: Application.delete_env(:ironhold, :webhook_signing_secret)
end
