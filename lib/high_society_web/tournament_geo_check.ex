defmodule HighSocietyWeb.TournamentGeoCheck do
  @moduledoc """
  Blocks tournament *registration* - not the rest of the site, not even
  other tournament pages like spectating a table or viewing results -
  from jurisdictions where sweepstakes entry is legally restricted. See
  `HighSociety.Tournaments.GeoRestriction` for the actual list and the
  "Eligibility" section of `/tournament/rules` for the public-facing
  version of this rule.

  Runs as an `on_mount` hook, not a router Plug, because `/tournament`
  used to share a `live_session` with other authenticated pages - a
  plain in-app `<.link navigate={...}>` between routes in the same
  live_session happens entirely over the already-open LiveView
  WebSocket, with no new HTTP request, so neither a Cloudflare edge rule
  nor a Plug in the `:browser` pipeline would ever see that navigation.
  `on_mount` re-runs on every mount, including that case - which is
  exactly why `/tournament` now has its own `live_session` in the
  router, scoped to just this hook plus authentication.

  Country/subdivision are read from the *Plug session* (the `session`
  argument here), not request headers - `HighSocietyWeb.Plugs.CaptureGeo`
  captures Cloudflare's geolocation headers into the session once, on
  whichever request actually established it, and Phoenix threads that
  same session into every subsequent `mount/3` call for the socket's
  lifetime (live-navigated or not). There's no fresh HTTP request to
  re-read headers from on a live-navigated mount, so the session is the
  only place this data can still be found by then.

  Fails open: if location can't be determined (local dev, direct access
  that bypasses Cloudflare, a renamed/missing header), the visitor is
  let through. Cloudflare's edge rule is the primary defense for real
  traffic; this hook exists to close the live-navigation gap above, not
  to be the sole line of defense - failing closed here would also lock
  every dev/staging environment out of ever testing registration.
  """
  use HighSocietyWeb, :verified_routes

  alias HighSociety.Tournaments.GeoRestriction

  def on_mount(:restrict_registration, _params, session, socket) do
    if GeoRestriction.restricted?(session["geo_country"], session["geo_subdivision"]) do
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          "Tournament registration isn't available in your region - see the Official " <>
            "Tournament Rules for details."
        )
        |> Phoenix.LiveView.redirect(to: ~p"/tournament/rules")

      {:halt, socket}
    else
      {:cont, socket}
    end
  end
end
