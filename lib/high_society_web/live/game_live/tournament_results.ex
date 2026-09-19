defmodule HighSocietyWeb.GameLive.TournamentResults do
  @moduledoc """
  Standings for one tournament - place, player, and (admins only, since
  it's how a winner gets manually paid) their Ethereum address plus KYC
  info. Doubles as the admin's payout checklist for 1st/2nd - see
  `HighSociety.Tournaments.standings/1`. KYC info is only ever shown for
  the 1st/2nd place rows, since no one else is ever required to provide
  it (see the "Prize Claim & Compliance Requirements" section of
  `/tournament/rules`).
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
      <div class="mx-auto max-w-3xl">
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
            <:col :let={entry} :if={@admin?} label="KYC info (1st/2nd only)">
              <.kyc_summary :if={entry.finish_place in [1, 2]} entry={entry} />
              <span :if={entry.finish_place not in [1, 2]} class="text-base-content/40">—</span>
            </:col>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :entry, :map, required: true

  defp kyc_summary(assigns) do
    ~H"""
    <div class="text-xs leading-relaxed">
      <p :if={full_name(@entry)} class="font-medium text-base-content">{full_name(@entry)}</p>
      <p :if={@entry.date_of_birth}>DOB {@entry.date_of_birth}</p>
      <p :if={full_address(@entry)}>{full_address(@entry)}</p>
      <span class={[
        "badge badge-xs mt-1",
        if(kyc_complete?(@entry), do: "badge-success", else: "badge-warning")
      ]}>
        {if kyc_complete?(@entry), do: "Complete", else: "Incomplete"}
      </span>
    </div>
    """
  end

  defp full_name(%{first_name: nil}), do: nil
  defp full_name(%{last_name: nil}), do: nil
  defp full_name(%{first_name: first, last_name: last}), do: "#{first} #{last}"

  defp full_address(entry) do
    case [entry.address, entry.city, entry.state, entry.zip_code] |> Enum.reject(&is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, ", ")
    end
  end

  @kyc_fields ~w(first_name last_name address city state zip_code date_of_birth)a

  defp kyc_complete?(entry),
    do: Enum.all?(@kyc_fields, &(Map.fetch!(entry, &1) not in [nil, ""]))

  defp place_label(nil), do: "Still playing"
  defp place_label(1), do: "1st"
  defp place_label(2), do: "2nd"
  defp place_label(3), do: "3rd"
  defp place_label(n), do: "#{n}th"
end
