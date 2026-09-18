defmodule HighSocietyWeb.Plugs.CaptureGeoTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias HighSocietyWeb.Plugs.CaptureGeo

  @session_opts Plug.Session.init(
                  store: :cookie,
                  key: "_test",
                  signing_salt: "test_salt",
                  encryption_salt: "test_encryption_salt"
                )

  defp conn_with_session(headers) do
    conn = conn(:get, "/tournament")

    conn =
      Enum.reduce(headers, conn, fn {key, value}, conn ->
        put_req_header(conn, key, value)
      end)

    conn
    |> Plug.Session.call(@session_opts)
    |> fetch_session()
  end

  test "captures cf-ipcountry and cf-region-code into the session" do
    conn =
      [{"cf-ipcountry", "CN"}, {"cf-region-code", "CN-BJ"}]
      |> conn_with_session()
      |> CaptureGeo.call([])

    assert get_session(conn, :geo_country) == "CN"
    assert get_session(conn, :geo_subdivision) == "CN-BJ"
  end

  test "leaves the session values nil when the headers are absent" do
    conn = [] |> conn_with_session() |> CaptureGeo.call([])

    assert get_session(conn, :geo_country) == nil
    assert get_session(conn, :geo_subdivision) == nil
  end

  test "falls back through alternate region header spellings" do
    conn = [{"cf-regioncode", "WA"}] |> conn_with_session() |> CaptureGeo.call([])
    assert get_session(conn, :geo_subdivision) == "WA"

    conn = [{"cf-region", "Washington"}] |> conn_with_session() |> CaptureGeo.call([])
    assert get_session(conn, :geo_subdivision) == "Washington"
  end

  test "prefers cf-region-code when multiple candidate headers are present" do
    conn =
      [{"cf-region-code", "WA"}, {"cf-regioncode", "WASH"}, {"cf-region", "Washington"}]
      |> conn_with_session()
      |> CaptureGeo.call([])

    assert get_session(conn, :geo_subdivision) == "WA"
  end
end
