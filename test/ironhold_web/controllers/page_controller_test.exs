defmodule IronholdWeb.PageControllerTest do
  use IronholdWeb.ConnCase, async: true

  test "GET / describes the project foundation", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~
             "Ironhold is a foundation in development for the secure and auditable receipt of webhooks."
  end
end
