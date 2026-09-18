defmodule HighSocietyWeb.DashboardLive do
  use HighSocietyWeb, :live_view

  alias HighSociety.Tournaments

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
      path: "/games/roulette",
      available: true
    },
    %{
      slug: "zombie-attack",
      name: "Zombie Attack",
      tagline: "Defend the house",
      description: "Place defenders across the lawn and hold the line through six waves.",
      icon: "hero-shield-exclamation",
      accent: "from-lime-500 to-emerald-600",
      path: "/games/zombie-attack",
      available: true
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    tournament = Tournaments.current_tournament()

    {:ok,
     assign(socket,
       games: @games,
       tournament: tournament,
       tournament_registered?: tournament_registered?(socket, tournament)
     )}
  end

  defp tournament_registered?(_socket, nil), do: false

  defp tournament_registered?(%{assigns: %{current_scope: %{user: %{}} = scope}}, tournament),
    do: not is_nil(Tournaments.get_entry(scope, tournament))

  defp tournament_registered?(_socket, _tournament), do: false

  defp tournament_headline(nil), do: "Poker Tournament — Coming Soon"
  defp tournament_headline(tournament), do: tournament.name

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} hero_video?={true}>
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

          <div id="hero-copy" phx-hook=".HeroReveal" class="relative mx-auto w-full max-w-5xl">
            <div data-reveal class="flex items-center gap-3 opacity-0 motion-reduce:opacity-100">
              <span class="h-px w-8 bg-zinc-300/70" />
              <p class="text-xs font-semibold uppercase tracking-[0.3em] text-zinc-200/90">
                Play, curated to a higher standard.
              </p>
            </div>

            <h1 class="mt-4">
              <span
                data-reveal
                class="block text-6xl leading-[1.15] font-bold tracking-tight text-white opacity-0 motion-reduce:opacity-100 sm:text-7xl lg:text-8xl"
              >
                High
              </span>
              <span
                data-reveal
                class="block bg-gradient-to-r from-zinc-100 via-slate-200 to-zinc-300 bg-clip-text text-6xl leading-[1.15] font-serif text-transparent italic opacity-0 [text-shadow:0_2px_30px_rgba(0,0,0,0.45)] motion-reduce:opacity-100 sm:text-7xl lg:text-8xl"
              >
                Society
              </span>
            </h1>

            <p
              data-reveal
              class="mt-6 max-w-md text-base text-white/75 opacity-0 motion-reduce:opacity-100 sm:text-lg"
            >
              Pick a table. Every game here is ready when you are.
            </p>

            <div data-reveal class="mt-8 opacity-0 motion-reduce:opacity-100">
              <a
                href="#games"
                class="inline-flex items-center rounded-sm border border-zinc-300/50 px-6 py-3 text-sm font-semibold text-zinc-100 backdrop-blur-sm transition-colors hover:border-zinc-200 hover:bg-zinc-300/10"
              >
                Enter the tables
              </a>
            </div>
          </div>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".HeroReveal">
            import { animate, stagger } from "@/vendor/anime.js"

            export default {
              mounted() {
                if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
                  return
                }

                const targets = this.el.querySelectorAll("[data-reveal]")

                animate(targets, {
                  opacity: [0, 1],
                  translateY: [16, 0],
                  delay: stagger(90, { start: 150 }),
                  duration: 700,
                  ease: "outQuad",
                })
              }
            }
          </script>

          <a
            href="#games"
            class="absolute right-6 bottom-6 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.2em] text-white/70 transition-colors hover:text-white sm:right-10 sm:bottom-10"
          >
            Discover <.icon name="hero-arrow-down" class="size-3.5 animate-bounce" />
          </a>
        </div>
      </:hero>

      <div id="games" phx-hook=".CardsReveal" class="mx-auto max-w-5xl scroll-mt-10">
        <div :if={!@tournament_registered?} class="mb-10">
          <div class="aura aura-gold">
            <div class="card overflow-hidden border border-base-300 bg-base-100">
              <div class="card-body flex-col items-center gap-4 text-center sm:flex-row sm:text-left">
                <img
                  src={~p"/images/tournament-trophy.webp"}
                  alt=""
                  class="size-14 shrink-0 rounded-full object-cover"
                />
                <div class="flex-1">
                  <h2 class="text-xl font-bold">{tournament_headline(@tournament)}</h2>
                  <p class="mt-1 text-sm text-base-content/70">
                    Free to enter, no purchase necessary. 1st place wins $75 in ETH plus an
                    exclusive High Society NFT — 2nd place wins $25 in ETH.
                  </p>
                </div>
                <.link
                  navigate={~p"/tournament"}
                  id="tournament-announcement-cta"
                  class="btn btn-primary shrink-0"
                >
                  Register now <span aria-hidden="true">&rarr;</span>
                </.link>
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <div
            :for={game <- @games}
            id={"game-card-#{game.slug}"}
            data-reveal-card
            class="group relative opacity-0 motion-reduce:opacity-100"
          >
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

        <div class="mt-10 flex justify-center">
          <div class="aura aura-gold">
            <div class="card border border-base-300 bg-base-100">
              <div class="card-body flex-row items-center gap-3 px-8 py-4">
                <.icon name="hero-sparkles" class="size-5 text-amber-500" />
                <p class="text-sm font-medium text-base-content/70">
                  More games coming soon&hellip;
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CardsReveal">
        import { animate, stagger, onScroll } from "@/vendor/anime.js"

        export default {
          mounted() {
            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
              return
            }

            const cards = this.el.querySelectorAll("[data-reveal-card]")

            this.animation = animate(cards, {
              opacity: [0, 1],
              translateY: [24, 0],
              delay: stagger(80),
              duration: 600,
              ease: "outQuad",
              autoplay: onScroll({
                target: this.el,
                repeat: false,
              }),
            })
          },
          destroyed() {
            this.animation?.revert()
          }
        }
      </script>
    </Layouts.app>
    """
  end
end
