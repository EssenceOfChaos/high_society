defmodule HighSociety.Tournaments.ZippopotamusTest do
  use ExUnit.Case, async: true

  alias HighSociety.Tournaments.Zippopotamus

  test "returns city and state for a valid US ZIP code" do
    Req.Test.stub(Zippopotamus, fn conn ->
      assert conn.request_path == "/us/19406"

      Req.Test.json(conn, %{
        "country" => "United States",
        "country abbreviation" => "US",
        "post code" => "19406",
        "places" => [
          %{
            "place name" => "King Of Prussia",
            "longitude" => "-75.3737",
            "latitude" => "40.0956",
            "state" => "Pennsylvania",
            "state abbreviation" => "PA"
          }
        ]
      })
    end)

    assert {:ok, %{city: "King Of Prussia", state: "PA"}} = Zippopotamus.lookup("US", "19406")
  end

  test "returns city and province for a valid Canadian postal code" do
    Req.Test.stub(Zippopotamus, fn conn ->
      assert conn.request_path == "/ca/T2S"

      Req.Test.json(conn, %{
        "places" => [%{"place name" => "Calgary", "state abbreviation" => "AB"}]
      })
    end)

    assert {:ok, %{city: "Calgary", state: "AB"}} = Zippopotamus.lookup("CA", "T2S")
  end

  test "drops a state abbreviation that isn't one of Regions' known codes" do
    Req.Test.stub(Zippopotamus, fn conn ->
      Req.Test.json(conn, %{
        "places" => [%{"place name" => "Somewhere", "state abbreviation" => "ZZ"}]
      })
    end)

    assert {:ok, %{city: "Somewhere", state: nil}} = Zippopotamus.lookup("US", "00000")
  end

  test "returns :error for an unrecognized postal code (404)" do
    Req.Test.stub(Zippopotamus, fn conn ->
      Plug.Conn.send_resp(conn, 404, "Not Found")
    end)

    assert :error = Zippopotamus.lookup("US", "00000")
  end

  test "returns :error for a country outside US/CA/MX without making a request" do
    Req.Test.stub(Zippopotamus, fn _conn ->
      flunk("should never make a request for an unsupported country")
    end)

    assert :error = Zippopotamus.lookup("FR", "75001")
  end
end
