defmodule IronholdWeb.WebhookControllerTest do
  use IronholdWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Ironhold.Repo
  alias Ironhold.Webhooks.{ReceivedWebhook, ReplayFingerprint}

  @authenticated_body_private_key :ironhold_authenticated_webhook_body
  @authenticated_signed_at_private_key :ironhold_authenticated_webhook_signed_at
  @accepted_event [:ironhold, :webhooks, :ingestion, :accepted]
  @rejected_event [:ironhold, :webhooks, :ingestion, :rejected]
  @max_body_size 262_144
  @replay_metadata_private_key :ironhold_authenticated_webhook_replay
  @signing_secret "tidewake_test_secret_not_for_production"
  @invalid_signature_response %{
    "errors" => [%{"detail" => "valid webhook signature required"}]
  }
  @valid_webhook %{
    id: "evt_123",
    type: "order.created",
    data: %{
      order_id: "123",
      status: "created"
    }
  }

  test "POST /api/webhooks accepts and stores a valid webhook", %{conn: conn} do
    attach_ingestion_events("evt_123")

    conn =
      conn
      |> post_json(Jason.encode!(@valid_webhook))

    assert_receive {:ingestion_event, @accepted_event, %{count: 1}, %{}, true}
    refute_receive {:ingestion_event, _, _, _, _}

    assert json_response(conn, 202) == %{
             "data" => %{
               "event_id" => "evt_123",
               "status" => "accepted"
             }
           }
  end

  test "POST /api/webhooks accepts application/json with charset", %{conn: conn} do
    body = Jason.encode!(%{@valid_webhook | id: "evt_with_charset"})

    conn = post_signed(conn, body, content_type: "application/json; charset=utf-8")

    assert json_response(conn, 202) == %{
             "data" => %{
               "event_id" => "evt_with_charset",
               "status" => "accepted"
             }
           }
  end

  test "POST /api/webhooks exposes only safe replay metadata after authentication", %{conn: conn} do
    body = Jason.encode!(%{@valid_webhook | id: "evt_replay_metadata"})
    timestamp = current_timestamp()

    conn = post_signed(conn, body, timestamp: timestamp)

    assert conn.private[@replay_metadata_private_key] == %{
             fingerprint: replay_fingerprint("evt_replay_metadata", timestamp, body),
             expires_at:
               timestamp
               |> String.to_integer()
               |> Kernel.+(300)
               |> DateTime.from_unix!()
           }

    refute Map.has_key?(conn.private, @authenticated_body_private_key)
    refute Map.has_key?(conn.private, @authenticated_signed_at_private_key)
  end

  test "POST /api/webhooks rejects a request without signing headers", %{conn: conn} do
    conn = post_with_content_type(conn, Jason.encode!(@valid_webhook), "application/json")

    assert_authentication_failure(conn)
  end

  test "POST /api/webhooks rejects an incorrect signature", %{conn: conn} do
    conn =
      post_signed(conn, Jason.encode!(@valid_webhook),
        signature: "v1=" <> String.duplicate("0", 64)
      )

    assert_authentication_failure(conn)
  end

  test "POST /api/webhooks rejects a stale timestamp", %{conn: conn} do
    timestamp = (System.system_time(:second) - 301) |> Integer.to_string()
    conn = post_signed(conn, Jason.encode!(@valid_webhook), timestamp: timestamp)

    assert_authentication_failure(conn)
  end

  test "POST /api/webhooks rejects a timestamp beyond the future limit", %{conn: conn} do
    timestamp = (System.system_time(:second) + 60) |> Integer.to_string()
    conn = post_signed(conn, Jason.encode!(@valid_webhook), timestamp: timestamp)

    assert_authentication_failure(conn)
  end

  test "POST /api/webhooks rejects a body changed after signing", %{conn: conn} do
    signed_body = Jason.encode!(@valid_webhook)
    changed_body = Jason.encode!(put_in(@valid_webhook, [:data, :status], "changed"))
    conn = post_signed(conn, changed_body, signed_body: signed_body)

    assert_authentication_failure(conn)
  end

  test "POST /api/webhooks rejects a header ID different from the body ID", %{conn: conn} do
    conn =
      post_signed(conn, Jason.encode!(@valid_webhook), header_id: "evt_different_header")

    assert_authentication_failure(conn)
  end

  test "POST /api/webhooks rejects a missing content type before the controller", %{conn: conn} do
    conn =
      conn
      |> accept_json()
      |> post(~p"/api/webhooks")

    assert_unsupported_media_type(conn)
    assert Repo.aggregate(ReceivedWebhook, :count) == 0
  end

  test "POST /api/webhooks rejects non-JSON media types before parsing", %{conn: _conn} do
    attach_ingestion_events()

    requests = [
      {"text/plain", Jason.encode!(@valid_webhook)},
      {"application/x-www-form-urlencoded", "id=evt_form&type=order.created"},
      {"multipart/form-data; boundary=ironhold", "--ironhold--"}
    ]

    Enum.each(requests, fn {content_type, body} ->
      response = post_with_content_type(build_conn(), body, content_type)

      assert_unsupported_media_type(response)

      assert_receive {:ingestion_event, @rejected_event, %{count: 1},
                      %{reason: :unsupported_media_type}, false}
    end)

    refute_receive {:ingestion_event, _, _, _, _}
    assert Repo.aggregate(ReceivedWebhook, :count) == 0
  end

  test "POST /api/webhooks rejects duplicate content-type headers", %{conn: conn} do
    body = Jason.encode!(%{@valid_webhook | id: "evt_duplicate_header"})

    conn =
      conn
      |> accept_json()
      |> prepend_req_headers([
        {"content-type", "application/json"},
        {"content-type", "text/plain"}
      ])
      |> post(~p"/api/webhooks", body)

    assert_unsupported_media_type(conn)
    assert Repo.aggregate(ReceivedWebhook, :count) == 0
  end

  test "POST /api/webhooks rejects an oversized form body without reading or exposing it",
       %{conn: conn} do
    marker = "rejected-form-body-must-not-leak"
    header_marker = "rejected-header-must-not-leak"
    body = "data=#{marker}" <> String.duplicate("x", @max_body_size)
    test_process = self()

    log =
      capture_log(fn ->
        response =
          post_with_content_type(
            conn,
            body,
            "application/x-www-form-urlencoded; marker=#{header_marker}"
          )

        send(test_process, {:unsupported_media_type_response, response})
      end)

    assert_receive {:unsupported_media_type_response, response}
    assert_unsupported_media_type(response)
    refute response.resp_body =~ marker
    refute response.resp_body =~ header_marker
    refute log =~ marker
    refute log =~ header_marker
    assert Repo.aggregate(ReceivedWebhook, :count) == 0
  end

  test "POST /api/webhooks accepts a real JSON body clearly below the limit", %{conn: conn} do
    body = json_body_with_size(200_000, "evt_below_limit")

    assert byte_size(body) == 200_000

    conn = post_json(conn, body)

    assert json_response(conn, 202) == %{
             "data" => %{
               "event_id" => "evt_below_limit",
               "status" => "accepted"
             }
           }
  end

  test "POST /api/webhooks accepts a body at the exact byte limit", %{conn: conn} do
    body = json_body_with_size(@max_body_size, "evt_at_limit")

    assert byte_size(body) == @max_body_size

    conn = post_json(conn, body)

    assert json_response(conn, 202) == %{
             "data" => %{
               "event_id" => "evt_at_limit",
               "status" => "accepted"
             }
           }
  end

  test "POST /api/webhooks rejects an oversized body without persisting and remains available",
       %{conn: conn} do
    marker = "rejected-body-must-not-leak"

    body =
      Jason.encode!(%{
        @valid_webhook
        | id: "evt_too_large",
          data: %{marker: marker, padding: String.duplicate("x", @max_body_size)}
      })

    assert byte_size(body) > @max_body_size

    test_process = self()

    log =
      capture_log(fn ->
        response = post_json(conn, body)
        send(test_process, {:oversized_response, response})
      end)

    assert_receive {:oversized_response, response}
    assert response.halted

    assert json_response(response, 413) == %{
             "errors" => [
               %{"detail" => "request body exceeds the 262144-byte limit"}
             ]
           }

    refute response.resp_body =~ marker
    refute log =~ marker
    assert Repo.aggregate(ReceivedWebhook, :count) == 0

    next_response =
      build_conn()
      |> post_json(Jason.encode!(%{@valid_webhook | id: "evt_after_rejection"}))

    assert json_response(next_response, 202) == %{
             "data" => %{
               "event_id" => "evt_after_rejection",
               "status" => "accepted"
             }
           }

    assert Repo.aggregate(ReceivedWebhook, :count) == 1
  end

  test "POST /api/webhooks accepts 255-character id and type fields", %{conn: conn} do
    event_id = String.duplicate("i", 255)
    webhook = %{@valid_webhook | id: event_id, type: String.duplicate("t", 255)}

    conn = post_json(conn, Jason.encode!(webhook))

    assert json_response(conn, 202) == %{
             "data" => %{
               "event_id" => event_id,
               "status" => "accepted"
             }
           }
  end

  test "POST /api/webhooks rejects a signed body without an id", %{conn: conn} do
    webhook = Map.delete(@valid_webhook, :id)

    conn = post_json(conn, Jason.encode!(webhook))

    assert_authentication_failure(conn)
  end

  test "POST /api/webhooks requires a non-empty string type", %{conn: conn} do
    conn = post_json(conn, Jason.encode!(%{@valid_webhook | type: "   "}))

    assert invalid_webhook_response(conn)
  end

  test "POST /api/webhooks sends signed semantic errors to normal validation", %{conn: conn} do
    conn = post_json(conn, Jason.encode!(%{@valid_webhook | data: ["not", "an", "object"]}))

    assert invalid_webhook_response(conn)
    assert Repo.aggregate(ReceivedWebhook, :count) == 0
  end

  test "POST /api/webhooks rejects an id longer than 255 characters", %{conn: conn} do
    conn =
      post_json(conn, Jason.encode!(%{@valid_webhook | id: String.duplicate("i", 256)}))

    assert invalid_webhook_response(conn)
  end

  test "POST /api/webhooks rejects a type longer than 255 characters", %{conn: conn} do
    conn =
      post_json(conn, Jason.encode!(%{@valid_webhook | type: String.duplicate("t", 256)}))

    assert invalid_webhook_response(conn)
  end

  test "POST /api/webhooks rejects a duplicate event id", %{conn: conn} do
    body = Jason.encode!(@valid_webhook)
    conn = post_json(conn, body)
    attach_ingestion_events()

    duplicate_conn =
      conn
      |> recycle()
      |> post_json(body)

    assert_receive {:ingestion_event, @rejected_event, %{count: 1},
                    %{reason: :duplicate_event_id}, false}

    refute_receive {:ingestion_event, _, _, _, _}

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

  defp post_json(conn, body), do: post_signed(conn, body)

  defp post_signed(conn, body, opts \\ []) do
    header_id = Keyword.get_lazy(opts, :header_id, fn -> body_id(body) end)
    timestamp = Keyword.get(opts, :timestamp, current_timestamp())
    signed_body = Keyword.get(opts, :signed_body, body)
    content_type = Keyword.get(opts, :content_type, "application/json")

    signature =
      Keyword.get_lazy(opts, :signature, fn ->
        signature(header_id, timestamp, signed_body)
      end)

    conn
    |> accept_json()
    |> put_req_header("content-type", content_type)
    |> put_req_header("tidewake-id", header_id)
    |> put_req_header("tidewake-timestamp", timestamp)
    |> put_req_header("tidewake-signature", signature)
    |> post(~p"/api/webhooks", body)
  end

  defp post_with_content_type(conn, body, content_type) do
    conn
    |> accept_json()
    |> put_req_header("content-type", content_type)
    |> post(~p"/api/webhooks", body)
  end

  defp json_body_with_size(size, event_id) do
    envelope = %{
      "id" => event_id,
      "type" => "order.created",
      "data" => %{"padding" => ""}
    }

    padding_size = size - byte_size(Jason.encode!(envelope))

    put_in(envelope, ["data", "padding"], String.duplicate("x", padding_size))
    |> Jason.encode!()
  end

  defp invalid_webhook_response(conn) do
    assert json_response(conn, 422) == %{
             "errors" => [
               %{
                 "detail" => "id, type, and data must be provided in the expected format"
               }
             ]
           }
  end

  defp assert_authentication_failure(conn) do
    assert conn.halted
    assert json_response(conn, 401) == @invalid_signature_response
    assert Repo.aggregate(ReceivedWebhook, :count) == 0
    refute Map.has_key?(conn.private, @replay_metadata_private_key)
  end

  defp assert_unsupported_media_type(conn) do
    assert conn.halted

    assert json_response(conn, 415) == %{
             "errors" => [
               %{"detail" => "content type must be application/json"}
             ]
           }
  end

  defp body_id(body) do
    case Jason.decode(body) do
      {:ok, %{"id" => id}} when is_binary(id) -> id
      _missing_or_invalid_id -> "evt_missing_body_id"
    end
  end

  defp current_timestamp, do: System.system_time(:second) |> Integer.to_string()

  defp signature(header_id, timestamp, body) do
    ["v1.", header_id, ".", timestamp, ".", body]
    |> IO.iodata_to_binary()
    |> then(&:crypto.mac(:hmac, :sha256, @signing_secret, &1))
    |> Base.encode16(case: :lower)
    |> then(&("v1=" <> &1))
  end

  defp replay_fingerprint(header_id, timestamp, body) do
    header_id
    |> signature(timestamp, body)
    |> ReplayFingerprint.derive()
  end

  defp attach_ingestion_events(event_id \\ nil) do
    handler_id = {__MODULE__, self(), make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [@accepted_event, @rejected_event],
        fn event, measurements, metadata, _config ->
          persisted =
            event == @accepted_event and
              not is_nil(Repo.get_by(ReceivedWebhook, event_id: event_id))

          send(test_pid, {:ingestion_event, event, measurements, metadata, persisted})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
