defmodule HighSocietyWeb.BadgesLive do
  use HighSocietyWeb, :live_view

  alias HighSociety.Badges

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    current_badge = Badges.for_active_days(user.active_days_count)

    {:ok,
     socket
     |> assign(:page_title, "Your Status")
     |> assign(:current_badge, current_badge)
     |> assign(:badges, Badges.all())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl">
        <div class="text-center">
          <.header>
            Your Status
            <:subtitle>
              Every badge is a milestone on your way to the top of High Society.
            </:subtitle>
          </.header>
        </div>

        <div class="rounded-box border border-base-300 bg-base-100 p-6 text-center">
          <p class="text-base text-base-content/80">
            The more you play, the more your status rises. Keep coming back to the tables and
            you'll climb the ranks below. So, pull up a chair. The table is waiting.
          </p>
        </div>

        <div class="mt-8 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          <div
            :for={badge <- @badges}
            id={"badge-#{badge.slug}"}
            class={[
              "relative flex flex-col items-center gap-2 rounded-box border p-4 text-center transition-opacity",
              badge.slug == @current_badge.slug && "border-primary bg-primary/5",
              badge.slug != @current_badge.slug && "border-base-300",
              badge.threshold > @current_badge.threshold && "opacity-40"
            ]}
          >
            <span
              :if={badge.slug == @current_badge.slug}
              class="badge badge-primary badge-sm absolute -top-2 left-1/2 -translate-x-1/2"
            >
              Current
            </span>

            <img
              src={"/images/badges/#{badge.slug}.png"}
              alt={badge.name}
              class="size-16 object-contain"
            />

            <div class="font-semibold">{badge.name}</div>
            <p class="text-xs text-base-content/60">{badge.tagline}</p>

            <.icon
              :if={badge.threshold > @current_badge.threshold}
              name="hero-lock-closed"
              class="absolute right-2 top-2 size-4 text-base-content/40"
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
