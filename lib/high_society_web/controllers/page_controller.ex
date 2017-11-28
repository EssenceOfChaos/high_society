defmodule HighSocietyWeb.PageController do
  use HighSocietyWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
