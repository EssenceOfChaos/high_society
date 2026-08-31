defmodule HighSocietyWeb.Presence do
  @moduledoc """
  Tracks who's currently connected to a Poker table's LiveView, for a live
  "N watching" count - distinct from who's actually seated, which comes
  from `HighSociety.Games.PokerTable`'s own authoritative state.
  """
  use Phoenix.Presence,
    otp_app: :high_society,
    pubsub_server: HighSociety.PubSub
end
