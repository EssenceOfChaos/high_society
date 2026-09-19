defmodule HighSocietyWeb.Plugs.CaptureGeo do
  @moduledoc """
  Captures Cloudflare's geolocation headers (if present) into the Plug
  session on every request, so `HighSocietyWeb.TournamentGeoCheck` can
  read them from any LiveView `mount/3` for this browser tab afterward -
  including a live-navigated mount, which never makes a fresh HTTP
  request and so never sees these headers directly. See that module's
  docs for why that distinction matters.

  `cf-ipcountry` is Cloudflare's standard header (an ISO 3166-1 alpha-2
  country code) and needs no configuration - it's sent by default. The
  region/state header does not come by default - it requires Cloudflare's
  "Add visitor location headers" Managed Transform to be turned on in the
  dashboard (Rules -> Managed Transforms) - and its exact name isn't
  something this codebase can verify independently, so `@region_headers`
  tries a short list of plausible names (in priority order) and uses
  whichever one is actually present, rather than requiring one exact
  guess to be right.

  A no-op when no geolocation headers are present at all (local dev,
  direct access that bypasses Cloudflare, or the transform isn't turned
  on) - the session values are simply left `nil`, which
  `HighSociety.Tournaments.GeoRestriction` treats as "not restricted"
  (fail open).
  """
  import Plug.Conn

  # Tried in order; the first one actually present in a request wins.
  # Confirmed against a live production log on 2026-09-18 (once "Add
  # visitor location headers" was genuinely enabled - an earlier check
  # that appeared Enabled turned out not to have actually been saved):
  # Cloudflare sends `cf-region-code` as a bare two-letter code (e.g.
  # `"PA"`, not `"US-PA"`), which is exactly what
  # `HighSociety.Tournaments.GeoRestriction` already normalizes for.
  @region_headers ~w(cf-region-code cf-regioncode cf-region)

  def init(opts), do: opts

  def call(conn, _opts) do
    country = conn |> get_req_header("cf-ipcountry") |> List.first()
    subdivision = region_header(conn)

    conn
    |> put_session(:geo_country, country)
    |> put_session(:geo_subdivision, subdivision)
  end

  defp region_header(conn) do
    Enum.find_value(@region_headers, fn name ->
      case get_req_header(conn, name) do
        [value | _] -> value
        [] -> nil
      end
    end)
  end
end
