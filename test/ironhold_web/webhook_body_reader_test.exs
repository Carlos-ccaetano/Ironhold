defmodule IronholdWeb.WebhookBodyReaderTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias IronholdWeb.WebhookBodyReader

  @authenticated_body_private_key :ironhold_authenticated_webhook_body
  @body_consumed_private_key :ironhold_authenticated_webhook_body_consumed

  test "returns the authenticated body byte for byte" do
    body = <<0, 255, ?{, ?}, 10>>
    conn = preserved_body_conn(body)

    assert {:ok, ^body, returned_conn} = WebhookBodyReader.read_body(conn, [])
    assert returned_conn.private[@body_consumed_private_key]
  end

  test "preserves JSON spaces, line endings, key order, and escapes" do
    body = "{\r\n  \"z\" : 1, \"a\": \"\\u0061\"\n}"
    conn = preserved_body_conn(body)

    assert {:ok, ^body, _conn} = WebhookBodyReader.read_body(conn, [])
  end

  test "returns a preserved body only once" do
    body = ~s({"id":"evt_test_123"})
    conn = preserved_body_conn(body)

    assert {:ok, ^body, consumed_conn} = WebhookBodyReader.read_body(conn, [])
    assert {:ok, "", returned_conn} = WebhookBodyReader.read_body(consumed_conn, [])
    assert returned_conn.private[@body_consumed_private_key]
  end

  test "delegates to Plug.Conn.read_body/2 without a preserved body" do
    body = "unrelated route body"
    conn = conn(:post, "/other", body)

    assert {:ok, ^body, _conn} = WebhookBodyReader.read_body(conn, [])
  end

  test "passes options to the fallback body reader" do
    conn = conn(:post, "/other", "abcdefgh")

    assert {:more, "abc", conn} = WebhookBodyReader.read_body(conn, length: 3)
    assert {:ok, "defgh", _conn} = Plug.Conn.read_body(conn, length: 5)
  end

  test "does not decode or normalize preserved bytes" do
    body = <<239, 187, 191>> <> "{\n\t\"b\":2, \"a\":1\n}"
    conn = preserved_body_conn(body)

    assert {:ok, returned_body, _conn} = WebhookBodyReader.read_body(conn, [])
    assert returned_body === body
  end

  defp preserved_body_conn(body) do
    :post
    |> conn("/api/webhooks", "")
    |> put_private(@authenticated_body_private_key, body)
  end
end
