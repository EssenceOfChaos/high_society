defmodule HighSocietyWeb.TournamentLive do
  @moduledoc """
  Sign-up for the poker tournament, and where a winner comes back to
  provide the KYC info required to actually collect a prize. The
  Ethereum address and every KYC field (name, address, date of birth)
  are optional at registration time - only the 1st/2nd place winners
  ever need them filled in, and only within 7 days of the tournament
  ending (see the "Prize Claim & Compliance Requirements" section of
  `/tournament/rules`). Nothing here moves crypto or verifies identity
  on its own.

  Reachable two ways: bare `/tournament` (the tournament
  `HighSociety.Tournaments.current_tournament/0` resolves - the one
  worth showing someone who isn't already registered for anything) and
  `/tournament/:id` (a specific tournament, reachable even after it's
  finished - the link a placement email sends a winner back to, since a
  finished tournament is never `current_tournament/0`).
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Tournaments

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    mount_tournament(Tournaments.get_tournament!(id), socket)
  end

  def mount(_params, _session, socket) do
    mount_tournament(Tournaments.current_tournament(), socket)
  end

  defp mount_tournament(nil, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Poker Tournament")
     |> assign(tournament: nil, registered?: false)}
  end

  defp mount_tournament(tournament, socket) do
    scope = socket.assigns.current_scope
    entry = Tournaments.get_entry(scope, tournament)
    changeset = Tournaments.change_entry(scope, tournament)

    {:ok,
     socket
     |> assign(:page_title, "Poker Tournament")
     |> assign(:tournament, tournament)
     |> assign(:registered?, not is_nil(entry))
     |> assign_form(changeset)}
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
        <div :if={Tournaments.scheduled_countdown?(@tournament)} class="mb-8 text-center">
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
            Tournament starts in
          </p>
          <.countdown id="tournament-countdown" target={@tournament.scheduled_start_at} />
        </div>

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
          <span>You're registered. Update your info below any time.</span>
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

          <div class="mt-6 rounded-box border border-base-300 bg-base-200 p-4">
            <h2 class="flex items-center gap-2 text-sm font-semibold">
              <.icon name="hero-shield-check" class="size-4" /> Prize verification info (optional)
            </h2>
            <p class="mt-1 text-xs text-base-content/60">
              Only needed if you place 1st or 2nd - required within 7 days of the tournament
              ending to receive your prize (identity verification, so we can't send payment to
              a sanctioned or blacklisted person or entity). Everyone else can leave this blank.
              You can fill it in now, or come back and add it later if you win.
            </p>

            <div class="mt-3 grid grid-cols-2 gap-3">
              <.input field={@form[:first_name]} type="text" label="First name" />
              <.input field={@form[:last_name]} type="text" label="Last name" />
            </div>
            <div class="mt-3">
              <.input field={@form[:address]} type="text" label="Street address" />
            </div>
            <div class="mt-3 grid grid-cols-3 gap-3">
              <.input field={@form[:city]} type="text" label="City" />
              <.input field={@form[:state]} type="text" label="State" />
              <.input field={@form[:zip_code]} type="text" label="ZIP code" />
            </div>
            <div class="mt-3">
              <.input field={@form[:date_of_birth]} type="date" label="Date of birth" />
            </div>
          </div>

          <.button phx-disable-with="Saving..." class="btn btn-primary mt-4 w-full">
            {if @registered?, do: "Update registration", else: "Register for the tournament"}
          </.button>
        </.form>

        <p class="mt-4 text-center text-xs text-base-content/50">
          Prizes are sent manually after the tournament, not automatically, and only to
          winners who provided this information. Adding it is entirely optional unless you
          win. See the
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
