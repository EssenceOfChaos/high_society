defmodule HighSocietyWeb.GameLive.TournamentResults do
  @moduledoc """
  Standings for one tournament - place, player, and (admins only, since
  it's how a winner gets manually paid) their Ethereum address. Doubles
  as the admin's payout checklist for 1st/2nd - see
  `HighSociety.Tournaments.standings/1`.
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Tournaments

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    tournament = Tournaments.get_tournament!(id)
    admin? = Accounts.admin?(socket.assigns.current_scope.user)

    {:ok,
     socket
     |> assign(:page_title, "#{tournament.name} – Results")
     |> assign(:tournament, tournament)
     |> assign(:admin?, admin?)
     |> assign(:standings, Tournaments.standings(tournament))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl">
        <.link
          navigate={~p"/tournament"}
          class="text-sm text-base-content/60 hover:text-base-content"
        >
          &larr; Tournament
        </.link>
        <.header>
          {@tournament.name} — Results
          <:subtitle :if={@tournament.status != "finished"}>
            Still in progress — standings update as players are eliminated.
          </:subtitle>
        </.header>

        <div class="mt-6 overflow-x-auto">
          <.table id="tournament-standings" rows={@standings}>
            <:col :let={entry} label="Place">{place_label(entry.finish_place)}</:col>
            <:col :let={entry} label="Player">{Accounts.display_name(entry.user)}</:col>
            <:col :let={entry} :if={@admin?} label="Ethereum address">
              {entry.ethereum_address || "—"}
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp place_label(nil), do: "Still playing"
  defp place_label(1), do: "1st"
  defp place_label(2), do: "2nd"
  defp place_label(3), do: "3rd"
  defp place_label(n), do: "#{n}th"
end
