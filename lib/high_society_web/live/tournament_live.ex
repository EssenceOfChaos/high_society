defmodule HighSocietyWeb.TournamentLive do
  @moduledoc """
  Sign-up for the poker tournament. Requires an account (see the
  `:require_authenticated_user` route) - the Ethereum address is the only
  optional field, collected purely so a human can manually send a winner's
  prize after the tournament. Nothing here moves crypto on its own.
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Tournaments

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :page_title, "Poker Tournament")

    case Tournaments.current_tournament() do
      nil ->
        {:ok, assign(socket, tournament: nil, registered?: false)}

      tournament ->
        scope = socket.assigns.current_scope
        entry = Tournaments.get_entry(scope, tournament)
        changeset = Tournaments.change_entry(scope, tournament)

        {:ok,
         socket
         |> assign(:tournament, tournament)
         |> assign(:registered?, not is_nil(entry))
         |> assign_form(changeset)}
    end
  end

  @impl true
  def render(%{tournament: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm text-center">
        <.header>Poker Tournament</.header>
        <p class="mt-4 text-base-content/70">
          No tournament is currently scheduled. Check back soon.
        </p>
        <.link navigate={~p"/tournament/rules"} class="link mt-2 inline-block text-sm">
          Official Tournament Rules
        </.link>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <img
            src={~p"/images/tournament-trophy.webp"}
            alt=""
            class="mx-auto size-20 rounded-full object-cover"
          />
          <.header>
            {@tournament.name}
            <:subtitle>
              1st place wins $75 in ETH plus an exclusive High Society NFT, 2nd place wins $25
              in ETH. Winners can optionally receive their prize to an Ethereum address of
              their choosing.
            </:subtitle>
          </.header>
        </div>

        <div :if={@tournament.status == "running"} class="mb-4 flex justify-center gap-2">
          <.link navigate={~p"/tournament/#{@tournament.id}/tables"} class="btn btn-sm btn-outline">
            Watch live tables
          </.link>
          <.link navigate={~p"/tournament/#{@tournament.id}/results"} class="btn btn-sm btn-outline">
            Standings
          </.link>
        </div>

        <div :if={@registered?} class="alert alert-success mb-4">
          <.icon name="hero-check-circle" class="size-5" />
          <span>You're registered. Update your Ethereum address below any time.</span>
        </div>

        <.form for={@form} id="tournament_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:ethereum_address]}
            type="text"
            label="Ethereum address (optional)"
            placeholder="0x..."
            autocomplete="off"
            spellcheck="false"
          />

          <.button phx-disable-with="Saving..." class="btn btn-primary w-full">
            {if @registered?, do: "Update registration", else: "Register for the tournament"}
          </.button>
        </.form>

        <p class="mt-4 text-center text-xs text-base-content/50">
          Prizes are sent manually after the tournament, not automatically, and only to
          winners who provided an address. Adding one is entirely optional. See the
          <.link navigate={~p"/tournament/rules"} class="link">Official Tournament Rules</.link>
          for eligibility, prize, and payout details.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"poker_tournament_entry" => params}, socket) do
    changeset =
      Tournaments.change_entry(socket.assigns.current_scope, socket.assigns.tournament, params)

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"poker_tournament_entry" => params}, socket) do
    case Tournaments.register(socket.assigns.current_scope, socket.assigns.tournament, params) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "You're registered! Check your email for confirmation.")
         |> assign(:registered?, true)
         |> assign_form(
           Tournaments.change_entry(socket.assigns.current_scope, socket.assigns.tournament)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "poker_tournament_entry"))
  end
end
