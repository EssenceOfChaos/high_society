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
      path: "/games/blackjack",
      available: true
    },
    %{
      slug: "poker",
      name: "Poker",
      tagline: "No-Limit Texas Hold'em",
      description: "Build the best hand and bluff your way to the pot.",
      icon: "hero-sparkles",
      accent: "from-indigo-500 to-violet-400",
      path: "/games/poker",
      available: true
    },
    %{
      slug: "battleship",
      name: "Battleship",
      tagline: "Sink the fleet",
      description: "Call your shots and hunt down the enemy fleet before they find yours.",
      icon: "hero-viewfinder-circle",
      accent: "from-sky-500 to-cyan-400",
      path: "/games/battleship",
      available: true
    },
    %{
      slug: "slots",
      name: "Slots",
      tagline: "Pull the lever",
      description: "Line up the reels and chase the jackpot.",
      icon: "hero-squares-2x2",
      accent: "from-amber-500 to-yellow-400",
      path: "/games/slots",
      available: true
    },
    %{
      slug: "roulette",
      name: "Roulette",
      tagline: "Place your bets",
      description: "Red or black, odd or even — let the wheel decide.",
      icon: "hero-adjustments-horizontal",
      accent: "from-red-500 to-rose-400",
      path: nil,
      available: false
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, games: @games, hero_video?: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:hero>
        <div class="fixed inset-0 overflow-hidden bg-neutral-900">
          <video
            class="absolute inset-0 size-full object-cover motion-reduce:hidden"
            autoplay
            muted
            loop
            playsinline
            preload="auto"
          >
            <source src={~p"/videos/hero-background.mp4"} type="video/mp4" />
          </video>

          <div class="absolute inset-0 bg-gradient-to-r from-black/75 via-black/45 to-black/20" />
          <div class="absolute inset-0 bg-gradient-to-b from-black/10 via-transparent to-black/40" />
        </div>

        <div class="relative z-10 flex h-[78vh] min-h-[520px] flex-col justify-center px-4 sm:px-6 lg:px-8">
          <div class="pointer-events-none absolute inset-x-0 bottom-0 h-32 bg-gradient-to-b from-transparent to-base-100 sm:h-40" />

          <div class="relative mx-auto w-full max-w-5xl">
            <div class="flex items-center gap-3">
              <span class="h-px w-8 bg-amber-400/70" />
              <p class="text-xs font-semibold uppercase tracking-[0.3em] text-amber-300/90">
                Play, curated to a higher standard.
              </p>
            </div>

            <h1 class="mt-4">
              <span class="block text-6xl leading-[1.15] font-bold tracking-tight text-white sm:text-7xl lg:text-8xl">
                High
              </span>
              <span class="block bg-gradient-to-r from-amber-200 via-amber-300 to-amber-500 bg-clip-text text-6xl leading-[1.15] font-serif text-transparent italic [text-shadow:0_2px_30px_rgba(0,0,0,0.45)] sm:text-7xl lg:text-8xl">
                Society
              </span>
            </h1>

            <p class="mt-6 max-w-md text-base text-white/75 sm:text-lg">
              Pick a table. Every game here is ready when you are.
            </p>

            <div class="mt-8">
              <a
                href="#games"
                class="inline-flex items-center rounded-sm border border-amber-300/50 px-6 py-3 text-sm font-semibold text-amber-100 backdrop-blur-sm transition-colors hover:border-amber-300 hover:bg-amber-400/10"
              >
                Enter the tables
              </a>
            </div>
          </div>

          <a
            href="#games"
            class="absolute right-6 bottom-6 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.2em] text-white/70 transition-colors hover:text-white sm:right-10 sm:bottom-10"
          >
            Discover <.icon name="hero-arrow-down" class="size-3.5 animate-bounce" />
          </a>
        </div>
      </:hero>

      <div id="games" class="mx-auto max-w-5xl scroll-mt-10">
        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <div :for={game <- @games} id={"game-card-#{game.slug}"} class="group relative">
            <div class={[
              "absolute -inset-1 rounded-box bg-gradient-to-br opacity-0 blur-lg transition-opacity duration-300",
              game.available && "group-hover:opacity-40",
              game.accent
            ]} />
            <div class="relative flex h-full flex-col rounded-box border border-base-300 bg-base-100 p-6 shadow-sm transition-all duration-300 group-hover:-translate-y-1 group-hover:shadow-lg">
              <div class={[
                "flex size-12 items-center justify-center rounded-full bg-gradient-to-br text-white",
                game.accent
              ]}>
                <.icon name={game.icon} class="size-6" />
              </div>

              <h2 class="mt-4 text-2xl font-semibold">{game.name}</h2>
              <p class="text-sm font-medium text-base-content/50">{game.tagline}</p>
              <p class="mt-2 flex-1 text-base text-base-content/70">{game.description}</p>

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
