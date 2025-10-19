defmodule GenServerIoWeb.PageControllerTest do
  use GenServerIoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "GenServer.io"
  end
end
