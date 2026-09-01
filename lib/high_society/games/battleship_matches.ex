defmodule HighSociety.Games.BattleshipMatches do
  @moduledoc """
  Read-only helper for the Battleship lobby. Unlike Poker's fixed,
  compile-time list of tables (`HighSociety.Games.PokerTables`), live
  Battleship matches are created dynamically and unbounded in number, so
  there's no fixed list of topics the lobby can pre-subscribe to -
  instead it queries Postgres for open matches on mount and live-updates
  via the shared `topic/0` every match broadcasts to on any status/seat
  change.
  """

  import Ecto.Query

  alias HighSociety.Games.BattleshipMatchState
  alias HighSociety.Repo

  @open_statuses ~w(waiting_for_opponent placing_fleets player_turn opponent_turn)

  @doc "The PubSub topic the lobby list live-updates from."
  def topic, do: "battleship_lobby"

  @doc "Open or in-progress matches, newest first, as lightweight lobby-row maps."
  @spec list_open() :: [%{slug: String.t(), wager: integer, status: String.t(), seat_count: 0..2}]
  def list_open do
    BattleshipMatchState
    |> where([m], m.status in ^@open_statuses)
    |> order_by([m], desc: m.inserted_at)
    |> Repo.all()
    |> Enum.map(&to_lobby_entry/1)
  end

  defp to_lobby_entry(row) do
    %{
      slug: row.slug,
      wager: row.wager,
      status: row.status,
      seat_count: Enum.count([row.seat_0_user_id, row.seat_1_user_id], & &1)
    }
  end
end
