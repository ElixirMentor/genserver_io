defmodule GenServerIoWeb.PageController do
  use GenServerIoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
