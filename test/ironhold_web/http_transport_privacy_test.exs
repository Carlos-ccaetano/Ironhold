defmodule IronholdWeb.HTTPTransportPrivacyTest do
  use ExUnit.Case, async: false

  alias IronholdWeb.HTTPAdapter
  @marker "f3-private-transport-marker"

  test "configured Bandit serves HTTP without formatting request-bearing errors, throws or exits" do
    assert IronholdWeb.Endpoint.config(:adapter) == HTTPAdapter

    [spec] =
      HTTPAdapter.child_specs(__MODULE__,
        otp_app: :ironhold,
        http: [ip: {127, 0, 0, 1}, port: 0, thousand_island_options: [num_acceptors: 1]]
      )

    pid = start_supervised!(spec)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        for {path, status} <- [{"ok", 200}, {"error", 500}, {"throw", 500}, {"exit", 500}] do
          {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5000)

          :ok =
            :gen_tcp.send(
              socket,
              "GET /#{path} HTTP/1.1\r\nHost: localhost\r\nAuthorization: #{@marker}\r\nConnection: close\r\n\r\n"
            )

          {:ok, response} = :gen_tcp.recv(socket, 0, 5000)
          :ok = :gen_tcp.close(socket)
          assert String.starts_with?(response, "HTTP/1.1 #{status}")
        end

        :ok = stop_supervised(spec.id)
        Logger.flush()
      end)

    refute logs =~ @marker
  end

  def init(options), do: options
  def call(%{request_path: "/error"}, _), do: raise(@marker)
  def call(%{request_path: "/throw"}, _), do: throw(@marker)
  def call(%{request_path: "/exit"}, _), do: exit(@marker)
  def call(conn, _options), do: Plug.Conn.send_resp(conn, 200, "ok")
end
