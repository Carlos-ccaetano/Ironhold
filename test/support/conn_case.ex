defmodule IronholdWeb.ConnCase do
  @moduledoc """
  Test case for requests that need an HTTP connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint IronholdWeb.Endpoint

      use IronholdWeb, :verified_routes
      import Plug.Conn
      import Phoenix.ConnTest
    end
  end

  setup tags do
    Ironhold.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
