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

  alias HighSociety.Games.PokerTables
  alias HighSociety.Tokens
  alias HighSociety.Tournaments
  alias HighSociety.Tournaments.Regions
  alias HighSociety.Tournaments.Zippopotamus

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
     |> assign(:zip_autofilled, %{city: nil, state: nil})
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
          </.header>
          <span class="badge badge-outline">No Limit Texas Hold'em</span>
          <p class="mt-2 text-sm text-base-content/70">
            1st place wins $75 in ETH plus an exclusive High Society NFT, 2nd place wins $25
            in ETH. A valid ETH address is required to receive the prize.
          </p>
        </div>

        <dl class="mt-6 mb-6 rounded-box border border-base-300 bg-base-200 p-4 text-sm">
          <h2 class="mb-2 text-sm font-semibold">Tournament details</h2>
          <div :if={@tournament.scheduled_start_at} class="flex justify-between gap-4 py-1">
            <dt class="text-base-content/70">Start time</dt>
            <dd class="text-right font-medium">
              <time
                id="tournament-start-time"
                phx-hook=".LocalTime"
                datetime={DateTime.to_iso8601(@tournament.scheduled_start_at)}
              >
                {Calendar.strftime(@tournament.scheduled_start_at, "%b %-d, %Y %-I:%M %p UTC")}
              </time>
              <span
                class="tooltip tooltip-left ml-1 align-middle before:max-w-56 before:whitespace-normal"
                tabindex="0"
                data-tip={"Shown in your device's local time zone. Starts at #{Calendar.strftime(@tournament.scheduled_start_at, "%-I:%M %p")} UTC."}
              >
                <.icon name="hero-information-circle" class="size-4 text-base-content/50" />
              </span>
            </dd>
          </div>
          <div class="flex justify-between py-1">
            <dt class="text-base-content/70">Starting chips</dt>
            <dd class="font-medium">{Tokens.format(@tournament.starting_stack)}</dd>
          </div>
          <div class="flex justify-between py-1">
            <dt class="text-base-content/70">Starting blinds</dt>
            <dd class="font-medium">{starting_blinds(@tournament)}</dd>
          </div>
          <div class="flex justify-between py-1">
            <dt class="text-base-content/70">Blinds increase every</dt>
            <dd class="font-medium">{@tournament.level_minutes} minutes</dd>
          </div>
          <div class="flex justify-between py-1">
            <dt class="text-base-content/70">Late registration</dt>
            <dd class="font-medium">
              Open for {@tournament.late_registration_minutes} minutes after start
            </dd>
          </div>
          <div class="flex justify-between py-1">
            <dt class="text-base-content/70">Rebuys</dt>
            <dd class="font-medium">Not allowed</dd>
          </div>
          <div class="flex justify-between py-1">
            <dt class="text-base-content/70">Minimum players</dt>
            <dd class="font-medium">{Tournaments.min_entrants()}</dd>
          </div>
          <div class="flex justify-between py-1">
            <dt class="text-base-content/70">Maximum players</dt>
            <dd class="font-medium">No limit ({PokerTables.seats()} per table)</dd>
          </div>
        </dl>

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
              <.input
                field={@form[:country]}
                type="select"
                label="Country"
                prompt="Select country"
                options={Enum.map(Regions.country_options(), fn {value, label} -> {label, value} end)}
              />
            </div>
            <div class="mt-3">
              <.input
                field={@form[:zip_code]}
                type="text"
                label="ZIP code"
                phx-blur="lookup_zip"
              />
            </div>
            <div class="mt-3">
              <.input field={@form[:address]} type="text" label="Street address" />
            </div>
            <div class="mt-3 grid grid-cols-2 gap-3">
              <.input field={@form[:city]} type="text" label="City" />
              <.input
                :if={state_options(@form)}
                field={@form[:state]}
                type="select"
                label={state_label(@form)}
                prompt={"Select #{state_label(@form)}"}
                options={Enum.map(state_options(@form), fn {value, label} -> {label, value} end)}
              />
              <.input
                :if={!state_options(@form)}
                field={@form[:state]}
                type="text"
                label="Region"
              />
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
        <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
          // Server renders UTC as a no-JS fallback; swap in the viewer's local time + zone.
          function render(el) {
            const date = new Date(el.getAttribute("datetime"))
            if (isNaN(date)) return
            el.textContent = date.toLocaleString(undefined, {
              month: "short",
              day: "numeric",
              year: "numeric",
              hour: "numeric",
              minute: "2-digit",
              timeZoneName: "short"
            })
          }

          export default {
            mounted() { render(this.el) },
            updated() { render(this.el) }
          }
        </script>
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

  def handle_event("lookup_zip", %{"value" => zip}, socket) do
    {:noreply, autofill_from_zip(socket, zip)}
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

  defp starting_blinds(%{blind_levels: [first | _]}) do
    # Stored as a JSON map, so keys come back as strings after a DB round trip.
    small = first["small_blind"] || first[:small_blind]
    big = first["big_blind"] || first[:big_blind]
    "#{Tokens.format(small)} / #{Tokens.format(big)}"
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "poker_tournament_entry"))
  end

  # Best-effort autofill from the ZIP code once a player tabs off it - only
  # for the three countries `Zippopotamus.lookup/2` supports. Only fills a
  # City/State field that's either still blank or still holds exactly what
  # a previous lookup put there (`@zip_autofilled`) - so re-tabbing off a
  # *changed* ZIP still refreshes City/State, but a value the player typed
  # themselves (or edited after an autofill) is never overwritten. Any
  # failure (bad ZIP, network error, country not selected yet) just leaves
  # the socket untouched - the fields stay editable by hand exactly as
  # before this existed.
  defp autofill_from_zip(socket, zip) do
    zip = String.trim(zip)
    changeset = socket.assigns.form.source
    country = Ecto.Changeset.get_field(changeset, :country)

    if zip != "" and country in ~w(US CA MX) do
      case Zippopotamus.lookup(country, zip) do
        {:ok, result} ->
          previously_autofilled = socket.assigns.zip_autofilled

          changeset =
            changeset
            |> fill_if_autofillable(:city, result.city, previously_autofilled.city)
            |> fill_if_autofillable(:state, result.state, previously_autofilled.state)

          socket
          |> assign(:zip_autofilled, %{city: result.city, state: result.state})
          |> assign_form(changeset)

        :error ->
          socket
      end
    else
      socket
    end
  end

  defp fill_if_autofillable(changeset, _field, nil, _previously_autofilled), do: changeset

  defp fill_if_autofillable(changeset, field, value, previously_autofilled) do
    current = Ecto.Changeset.get_field(changeset, field)

    if blank?(current) or current == previously_autofilled do
      Ecto.Changeset.put_change(changeset, field, value)
    else
      changeset
    end
  end

  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(value) == ""

  # `nil` (no country chosen yet) or any country outside the three the form
  # has a fixed list for - renders State as free text ("Region") instead.
  defp state_options(form), do: form[:country].value |> to_string() |> Regions.state_options_for()

  defp state_label(form), do: form[:country].value |> to_string() |> Regions.state_field_label()
end
