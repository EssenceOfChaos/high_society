defmodule HighSocietyWeb.PageControllerTest do
  use HighSocietyWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get conn, "/"
    assert html_response(conn, 200) =~ "Welcome to High Society"
  end
end
