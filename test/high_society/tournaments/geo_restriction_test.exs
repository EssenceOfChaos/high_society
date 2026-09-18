defmodule HighSociety.Tournaments.GeoRestrictionTest do
  use ExUnit.Case, async: true

  alias HighSociety.Tournaments.GeoRestriction

  describe "restricted?/2" do
    test "restricted countries" do
      assert GeoRestriction.restricted?("CN", nil)
      assert GeoRestriction.restricted?("IR", nil)
      assert GeoRestriction.restricted?("KP", nil)
      assert GeoRestriction.restricted?("SY", nil)
      assert GeoRestriction.restricted?("CU", nil)
    end

    test "restricted US subdivisions, in either ISO 3166-2 or bare-code form" do
      assert GeoRestriction.restricted?("US", "US-WA")
      assert GeoRestriction.restricted?("US", "US-ID")
      assert GeoRestriction.restricted?("US", "WA")
      assert GeoRestriction.restricted?("US", "ID")
    end

    test "subdivision matching is case-insensitive" do
      assert GeoRestriction.restricted?("US", "wa")
      assert GeoRestriction.restricted?("US", "us-wa")
    end

    test "an unrestricted country/subdivision is allowed" do
      refute GeoRestriction.restricted?("US", "US-CA")
      refute GeoRestriction.restricted?("US", "CA")
      refute GeoRestriction.restricted?("GB", nil)
      refute GeoRestriction.restricted?("CA", nil)
    end

    test "unknown location (both nil) fails open - never restricted" do
      refute GeoRestriction.restricted?(nil, nil)
    end
  end
end
