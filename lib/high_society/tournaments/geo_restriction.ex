defmodule HighSociety.Tournaments.GeoRestriction do
  @moduledoc """
  Which jurisdictions are excluded from poker tournament *registration* -
  see the "Eligibility" section of `/tournament/rules` and
  `HighSocietyWeb.TournamentGeoCheck`, the only place this is enforced.
  Deliberately scoped to registration only, not the rest of the site
  (including spectating a table, viewing results, or any other game) -
  it's entry into the prize drawing that triggers the restricted
  jurisdictions' sweepstakes law, not casual use of a free, no-prize
  game elsewhere on the site.
  """

  @restricted_countries ~w(CN IR KP SY CU)
  # Bare two-letter codes - matched against `subdivision` after stripping
  # any "US-" prefix and upcasing, since Cloudflare's *header* value for
  # this (as opposed to the "US-WA"-style value its WAF rules engine
  # field uses) isn't confirmed to carry the country prefix at all - see
  # `HighSocietyWeb.Plugs.CaptureGeo`.
  @restricted_us_subdivision_codes ~w(WA ID)

  @doc """
  Whether a visitor from `country` (an ISO 3166-1 alpha-2 code, e.g.
  `"CN"`) and/or `subdivision` (a US state code, either bare - `"WA"` -
  or ISO 3166-2 - `"US-WA"`, matched case-insensitively either way) is
  excluded from tournament registration. Either argument may be `nil`
  (location unknown) - `nil` never matches, so an unknown location is
  never treated as restricted (fail open; see
  `HighSocietyWeb.Plugs.CaptureGeo` for why location can legitimately be
  unknown).
  """
  @spec restricted?(String.t() | nil, String.t() | nil) :: boolean()
  def restricted?(country, subdivision) do
    country in @restricted_countries or restricted_subdivision?(subdivision)
  end

  defp restricted_subdivision?(nil), do: false

  defp restricted_subdivision?(subdivision) do
    subdivision
    |> String.upcase()
    |> String.trim_leading("US-")
    |> then(&(&1 in @restricted_us_subdivision_codes))
  end
end
