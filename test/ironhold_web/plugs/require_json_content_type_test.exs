defmodule IronholdWeb.Plugs.RequireJsonContentTypeTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias IronholdWeb.Plugs.RequireJsonContentType

  @opts RequireJsonContentType.init([])

  for method <- ~w(POST PUT PATCH DELETE) do
    test "requires content type for API #{method} requests" do
      conn =
        unquote(method)
        |> conn("/api/webhooks")
        |> RequireJsonContentType.call(@opts)

      assert conn.halted
      assert conn.status == 415
    end
  end

  test "allows one valid application/json header" do
    conn =
      :post
      |> conn("/api/webhooks")
      |> put_req_header("content-type", "application/json; charset=utf-8")
      |> RequireJsonContentType.call(@opts)

    refute conn.halted
  end

  test "rejects duplicate content-type headers even when they match" do
    conn =
      :post
      |> conn("/api/webhooks")
      |> prepend_req_headers([
        {"content-type", "application/json"},
        {"content-type", "application/json"}
      ])
      |> RequireJsonContentType.call(@opts)

    assert conn.halted
    assert conn.status == 415
  end

  test "rejects an ambiguous combined content-type header" do
    conn =
      :post
      |> conn("/api/webhooks")
      |> put_req_header("content-type", "application/json, text/plain")
      |> RequireJsonContentType.call(@opts)

    assert conn.halted
    assert conn.status == 415
  end

  test "does not affect non-body API methods" do
    conn = conn(:get, "/api/webhooks")

    refute RequireJsonContentType.call(conn, @opts).halted
  end

  test "does not affect HTML requests" do
    conn = conn(:post, "/")

    refute RequireJsonContentType.call(conn, @opts).halted
  end
end
