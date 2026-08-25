defmodule HighSocietyWeb.DashboardLive do
  use HighSocietyWeb, :live_view

  @games [
    %{
      slug: "war",
      name: "War",
      tagline: "The classic showdown",
      description:
        "Flip cards head-to-head against the computer. Highest card takes the pile — ties go to war.",
      icon: "hero-bolt",
      accent: "from-rose-500 to-orange-400",
      path: "/games/war",
      available: true
    },
    %{
      slug: "blackjack",
      name: "Blackjack",
      tagline: "Beat the dealer",
      description: "Get as close to 21 as you can without going bust.",
      icon: "hero-currency-dollar",
      accent: "from-emerald-500 to-teal-400",
      path: nil,
      available: false
    },
    %{
      slug: "poker",
      name: "Poker",
      tagline: "Five-card draw",
      description: "Build the best hand and bluff your way to the pot.",
      icon: "hero-sparkles",
      accent: "from-indigo-500 to-violet-400",
      path: nil,
      available: false
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :games, @games)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl">
        <div class="text-center">
          <h1 class="text-4xl font-bold tracking-tight sm:text-5xl">High Society</h1>
          <p class="mt-3 text-base-content/70 text-lg">
            Pick a table. Every game here is ready when you are.
          </p>
        </div>

        <div class="mt-12 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <div :for={game <- @games} id={"game-card-#{game.slug}"} class="group relative">
            <div class={[
              "absolute inset-0 rounded-box bg-gradient-to-br opacity-0 blur transition-opacity duration-300",
              game.available && "group-hover:opacity-20",
              game.accent
            ]} />
            <div class="relative flex h-full flex-col rounded-box border border-base-300 bg-base-100 p-6 shadow-sm transition-all duration-300 group-hover:-translate-y-1 group-hover:shadow-lg">
              <div class={[
                "flex size-12 items-center justify-center rounded-full bg-gradient-to-br text-white",
                game.accent
              ]}>
                <.icon name={game.icon} class="size-6" />
              </div>

              <h2 class="mt-4 text-xl font-semibold">{game.name}</h2>
              <p class="text-sm font-medium text-base-content/50">{game.tagline}</p>
              <p class="mt-2 flex-1 text-sm text-base-content/70">{game.description}</p>

              <div class="mt-6">
                <%= if game.available do %>
                  <.link
                    navigate={game.path}
                    id={"play-#{game.slug}"}
                    class="btn btn-primary btn-block"
                  >
                    Play now <span aria-hidden="true">&rarr;</span>
                  </.link>
                <% else %>
                  <button class="btn btn-block btn-disabled" disabled>
                    Coming soon
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
