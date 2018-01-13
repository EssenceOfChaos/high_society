defmodule HighSocietyWeb.PageController do
  use HighSocietyWeb, :controller

  def index(conn, _params) do
    IO.inspect conn
    render conn, "index.html"
  end
end
