defmodule HighSocietyWeb.GameLive.Leaderboard do
  @moduledoc """
  Per-game leaderboard - Blackjack or Poker, picked by `@live_action`
  (see the two routes in the router). Ranks players by lifetime net
  Tokens won - see `HighSociety.Leaderboards.top_players/2` for exactly
  what that means and its one documented gap (an in-progress Poker
  session isn't counted until the player cashes out).
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Leaderboards
  alias HighSociety.Tokens

  @impl true
  def mount(_params, _session, socket) do
    entries = Leaderboards.top_players(socket.assigns.live_action)

    {:ok,
     assign(socket,
       page_title: "#{game_name(socket.assigns.live_action)} Leaderboard",
       entries: entries
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <.link
          navigate={game_path(@live_action)}
          class="text-sm text-base-content/60 hover:text-base-content"
        >
          &larr; Back to {game_name(@live_action)}
        </.link>

        <div class="mt-1">
          <.header>
            {game_name(@live_action)} Leaderboard
            <:subtitle>Ranked by lifetime net Tokens won.</:subtitle>
          </.header>
        </div>

        <p :if={@entries == []} class="mt-6 text-sm text-base-content/60">
          No one has played {game_name(@live_action)} yet - be the first!
        </p>

        <div :if={@entries != []} class="mt-6 overflow-x-auto">
          <.table
            id="leaderboard"
            rows={@entries}
            row_class={fn entry -> entry.user.id == @current_scope.user.id && "bg-primary/10" end}
          >
            <:col :let={entry} label="Rank">#{entry.rank}</:col>
            <:col :let={entry} label="Badge">
              <.player_badge
                active_days_count={entry.user.active_days_count}
                class="size-8"
                tooltip_position="tooltip-right"
              />
            </:col>
            <:col :let={entry} label="Player">
              <span class={[
                "font-semibold",
                entry.user.id == @current_scope.user.id && "text-primary"
              ]}>
                {entry.display_name}
              </span>
            </:col>
            <:col :let={entry} label="Tokens Won">
              <span class={["font-semibold", amount_class(entry.net_tokens_won)]}>
                {signed_amount(entry.net_tokens_won)} Tokens
              </span>
            </:col>
            <:col :let={entry} label="Member Since">{member_since_text(entry.member_since)}</:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp game_name(:blackjack), do: "Blackjack"
  defp game_name(:poker), do: "Poker"

  defp game_path(:blackjack), do: ~p"/games/blackjack"
  defp game_path(:poker), do: ~p"/games/poker"

  defp signed_amount(amount) when amount >= 0, do: "+#{Tokens.format(amount)}"
  defp signed_amount(amount), do: Tokens.format(amount)

  defp amount_class(amount) when amount >= 0, do: "text-success"
  defp amount_class(_amount), do: "text-error"

  # A rough, human "member since" duration rather than a calendar date -
  # this page is about bragging rights, not precise record-keeping.
  defp member_since_text(%DateTime{} = inserted_at) do
    case DateTime.diff(DateTime.utc_now(), inserted_at, :day) do
      days when days < 1 -> "New today"
      1 -> "1 day"
      days when days < 30 -> "#{days} days"
      days when days < 365 -> pluralize(div(days, 30), "month")
      days -> pluralize(div(days, 365), "year")
    end
  end

  defp pluralize(1, unit), do: "1 #{unit}"
  defp pluralize(n, unit), do: "#{n} #{unit}s"
end
