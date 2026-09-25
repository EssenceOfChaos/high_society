defmodule HighSocietyWeb.AdminLive.Tournaments do
  @moduledoc """
  Admin-only tournament management: create a tournament (using
  `HighSociety.Games.TournamentBlinds`' default blind schedule, with the
  starting stack/level/break timing knobs editable) and manually start a
  scheduled one - the only way a tournament actually begins, see
  `HighSociety.Tournaments.start!/1`. Gated by the `:require_admin`
  on_mount - see `HighSocietyWeb.UserAuth`.
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Tournaments

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tournaments")
     |> assign(:tournaments, tournaments_with_entrant_counts())
     |> assign_form(Tournaments.change_tournament())}
  end

  @impl true
  def handle_event("validate", %{"poker_tournament" => params}, socket) do
    changeset = Tournaments.change_tournament(params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("create", %{"poker_tournament" => params}, socket) do
    case Tournaments.create_tournament(params) do
      {:ok, tournament} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{tournament.name} created.")
         |> assign(:tournaments, tournaments_with_entrant_counts())
         |> assign_form(Tournaments.change_tournament())}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("start", %{"id" => id}, socket) do
    tournament = Tournaments.get_tournament!(id)

    case Tournaments.start!(tournament) do
      {:ok, started} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{started.name} is running.")
         |> assign(:tournaments, tournaments_with_entrant_counts())}

      {:error, :not_enough_entrants} ->
        {:noreply, put_flash(socket, :error, "Needs at least 2 registered entrants to start.")}

      {:error, :already_started} ->
        {:noreply, put_flash(socket, :error, "That tournament has already started.")}
    end
  end

  defp tournaments_with_entrant_counts do
    Enum.map(Tournaments.list_tournaments(), fn tournament ->
      %{tournament: tournament, entrant_count: length(Tournaments.standings(tournament))}
    end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "poker_tournament"))
  end

  defp status_badge_class("scheduled"), do: "badge-neutral"
  defp status_badge_class("running"), do: "badge-success"
  defp status_badge_class("finished"), do: "badge-info"
  defp status_badge_class("cancelled"), do: "badge-error"

  # Shown exactly as entered/stored - UTC, not the admin's local time (see
  # the "Scheduled start (UTC)" field above) - so this always matches what
  # was typed in, with no silent timezone conversion to get wrong.
  defp format_scheduled_start(nil), do: "—"

  defp format_scheduled_start(%DateTime{} = dt),
    do: Calendar.strftime(dt, "%b %-d, %Y %-I:%M %p UTC")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <.header>
          Tournaments
          <:subtitle>Create a tournament and start it manually when you're ready.</:subtitle>
        </.header>

        <div class="mt-6 rounded-box border border-base-300 bg-base-100 p-4">
          <h2 class="text-lg font-semibold">New tournament</h2>

          <.form for={@form} id="tournament_form" phx-submit="create" phx-change="validate">
            <.input field={@form[:name]} type="text" label="Name" />
            <.input
              field={@form[:scheduled_start_at]}
              type="datetime-local"
              label="Scheduled start (UTC)"
            />
            <p class="-mt-3 mb-3 text-xs text-base-content/60">
              Entered and stored as UTC, not your local time - convert first (e.g. 5:00 PM Eastern
              is 9:00 PM UTC during Eastern Daylight Time, 10:00 PM UTC during Eastern Standard
              Time). Shown as a countdown on the registration page; leave blank for none.
            </p>
            <.input field={@form[:starting_stack]} type="number" label="Starting stack" />
            <.input field={@form[:level_minutes]} type="number" label="Minutes per level" />
            <.input field={@form[:break_every_minutes]} type="number" label="Break every (minutes)" />
            <.input field={@form[:break_minutes]} type="number" label="Break length (minutes)" />
            <.input
              field={@form[:late_registration_minutes]}
              type="number"
              label="Late registration window (minutes)"
            />

            <.button phx-disable-with="Creating..." class="btn btn-primary mt-2">
              Create tournament
            </.button>
          </.form>
        </div>

        <div class="mt-8">
          <h2 class="text-lg font-semibold">All tournaments</h2>

          <p :if={@tournaments == []} class="mt-2 text-sm text-base-content/60">
            No tournaments yet.
          </p>

          <div :if={@tournaments != []} class="mt-4 overflow-x-auto">
            <.table id="admin-tournaments" rows={@tournaments}>
              <:col :let={%{tournament: t}} label="Name">{t.name}</:col>
              <:col :let={%{tournament: t}} label="Status">
                <span class={["badge", status_badge_class(t.status)]}>{t.status}</span>
              </:col>
              <:col :let={%{tournament: t}} label="Scheduled start">
                {format_scheduled_start(t.scheduled_start_at)}
              </:col>
              <:col :let={%{entrant_count: count}} label="Entrants">{count}</:col>
              <:col :let={%{tournament: t}} label="">
                <button
                  :if={t.status == "scheduled"}
                  phx-click="start"
                  phx-value-id={t.id}
                  id={"start-tournament-#{t.id}"}
                  class="btn btn-sm btn-primary"
                  data-confirm={"Start #{t.name} now? This can't be undone."}
                >
                  Start
                </button>
              </:col>
            </.table>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
