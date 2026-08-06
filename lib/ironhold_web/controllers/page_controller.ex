defmodule IronholdWeb.PageController do
  use IronholdWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
