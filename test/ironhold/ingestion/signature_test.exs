defmodule Ironhold.Ingestion.SignatureTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ironhold.Ingestion.Signature

  @event_id "evt_test_123"
  @timestamp "1700000000"
  @current_time 1_700_000_000
  @body ~S({"data":{"ok":true},"id":"evt_test_123","type":"test.ping"})
  @secret "tidewake_test_secret_not_for_production"
  @signature "v1=3323d158355377e1b2d7515e31a40365a48ff11d427a8a8f62cfda1e4bf92128"
  @authenticated_result %{event_id: @event_id, signed_at: @current_time}

  test "verifies the exact shared Tidewake vector" do
    assert Signature.verify(
             @event_id,
             @timestamp,
             @signature,
             @body,
             @secret,
             @current_time
           ) == {:ok, @authenticated_result}
  end

  test "returns only normalized authenticated values on success" do
    result =
      Signature.verify(
        @event_id,
        @timestamp,
        @signature,
        @body,
        @secret,
        @current_time
      )

    assert result == {:ok, @authenticated_result}
    refute inspect(result) =~ @secret
    refute inspect(result) =~ @signature
  end

  test "accepts the inclusive past boundary" do
    timestamp = Integer.to_string(@current_time - 300)

    assert verify(timestamp, signature_for(timestamp)) ==
             {:ok, %{event_id: @event_id, signed_at: @current_time - 300}}
  end

  test "accepts the inclusive future boundary" do
    timestamp = Integer.to_string(@current_time + 30)

    assert verify(timestamp, signature_for(timestamp)) ==
             {:ok, %{event_id: @event_id, signed_at: @current_time + 30}}
  end

  test "derives expiration from the existing past-age window" do
    assert Signature.acceptance_expires_at(@current_time) ==
             {:ok, ~U[2023-11-14 22:18:20Z]}
  end

  test "rejects one second beyond the past boundary" do
    timestamp = Integer.to_string(@current_time - 301)

    assert verify(timestamp, signature_for(timestamp)) == {:error, :invalid_signature}
  end

  test "rejects one second beyond the future boundary" do
    timestamp = Integer.to_string(@current_time + 31)

    assert verify(timestamp, signature_for(timestamp)) == {:error, :invalid_signature}
  end

  test "rejects malformed timestamps with the same public error" do
    for timestamp <- [nil, "", "-1700000000", "+1700000000", "1700000000.0", " 1700000000", "1e9"] do
      assert verify(timestamp, @signature) == {:error, :invalid_signature}
    end
  end

  test "rejects an empty ID" do
    assert Signature.verify("", @timestamp, @signature, @body, @secret, @current_time) ==
             {:error, :invalid_signature}
  end

  test "rejects absent or malformed signatures with the same public error" do
    signatures = [
      nil,
      "",
      String.duplicate("0", 64),
      "v2=" <> String.duplicate("0", 64),
      "v1=" <> String.duplicate("g", 64)
    ]

    for signature <- signatures do
      assert verify(@timestamp, signature) == {:error, :invalid_signature}
    end
  end

  test "rejects uppercase hexadecimal" do
    digest = String.replace_prefix(@signature, "v1=", "")
    uppercase_signature = "v1=" <> String.upcase(digest)

    assert verify(@timestamp, uppercase_signature) == {:error, :invalid_signature}
  end

  test "rejects tampered body, ID, timestamp, or signature" do
    tampered_signature = String.replace_suffix(@signature, "8", "9")

    assert Signature.verify(
             @event_id,
             @timestamp,
             @signature,
             @body <> " ",
             @secret,
             @current_time
           ) == {:error, :invalid_signature}

    assert Signature.verify(
             "evt_test_124",
             @timestamp,
             @signature,
             @body,
             @secret,
             @current_time
           ) == {:error, :invalid_signature}

    assert verify("1700000001", @signature) == {:error, :invalid_signature}
    assert verify(@timestamp, tampered_signature) == {:error, :invalid_signature}
  end

  test "rejects signatures with incompatible lengths before safe comparison" do
    for digest_size <- [63, 65] do
      signature = "v1=" <> String.duplicate("0", digest_size)

      assert verify(@timestamp, signature) == {:error, :invalid_signature}
    end
  end

  test "returns the same public error for invalid body, secret, or current time" do
    assert Signature.verify(@event_id, @timestamp, @signature, nil, @secret, @current_time) ==
             {:error, :invalid_signature}

    assert Signature.verify(@event_id, @timestamp, @signature, @body, "too-short", @current_time) ==
             {:error, :invalid_signature}

    assert Signature.verify(@event_id, @timestamp, @signature, @body, @secret, nil) ==
             {:error, :invalid_signature}
  end

  test "does not log successful or rejected verification data" do
    log =
      capture_log([level: :debug], fn ->
        assert verify(@timestamp, @signature) == {:ok, @authenticated_result}

        assert verify(@timestamp, String.replace_suffix(@signature, "8", "9")) ==
                 {:error, :invalid_signature}
      end)

    assert log == ""
  end

  defp verify(timestamp, signature) do
    Signature.verify(@event_id, timestamp, signature, @body, @secret, @current_time)
  end

  defp signature_for(timestamp) do
    canonical = IO.iodata_to_binary(["v1.", @event_id, ".", timestamp, ".", @body])

    digest =
      :crypto.mac(:hmac, :sha256, @secret, canonical)
      |> Base.encode16(case: :lower)

    "v1=" <> digest
  end
end
