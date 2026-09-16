defmodule HighSocietyWeb.TokensLive do
  @moduledoc """
  Public explainer page for High Society Tokens - what they are, how
  they're earned, and how they'll eventually be redeemed. No sensitive
  data here, so it's reachable with or without an account (see the
  `:current_user` live_session in the router).
  """
  use HighSocietyWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "High Society Tokens")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:hero>
        <div class="fixed inset-0 overflow-hidden bg-gradient-to-b from-neutral-950 via-neutral-900 to-base-100">
          <div class="pointer-events-none absolute left-1/2 top-1/3 size-[28rem] -translate-x-1/2 -translate-y-1/2 rounded-full bg-amber-400/20 blur-[100px]" />
        </div>

        <div
          id="tokens-hero"
          phx-hook=".HeroTokenReveal"
          class="relative z-10 flex min-h-[80vh] flex-col items-center justify-center px-4 py-24 text-center sm:px-6 lg:px-8"
        >
          <.hero_token_coin id="hero-token-coin" class="relative size-32 sm:size-40" />

          <h1
            class="relative mt-8 text-5xl font-bold tracking-tight text-white opacity-0 motion-reduce:opacity-100 sm:text-6xl lg:text-7xl"
            data-hero-reveal
          >
            High Society
            <span class="block bg-gradient-to-r from-amber-200 via-yellow-300 to-amber-400 bg-clip-text font-serif italic text-transparent">
              Tokens
            </span>
          </h1>

          <p
            class="relative mt-6 max-w-md text-base text-white/70 opacity-0 motion-reduce:opacity-100 sm:text-lg"
            data-hero-reveal
          >
            The currency of the tables — earned by playing.
          </p>

          <a
            href="#what-are-tokens"
            class="relative mt-10 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.2em] text-white/60 opacity-0 transition-colors hover:text-white motion-reduce:opacity-100"
            data-hero-reveal
          >
            Keep scrolling <.icon name="hero-arrow-down" class="size-3.5 animate-bounce" />
          </a>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".HeroTokenReveal">
            import { animate, stagger } from "@/vendor/anime.js"

            export default {
              mounted() {
                if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
                  return
                }

                animate(this.el.querySelectorAll("[data-hero-reveal]"), {
                  opacity: [0, 1],
                  translateY: [16, 0],
                  delay: stagger(100, { start: 250 }),
                  duration: 700,
                  ease: "outQuad",
                })
              }
            }
          </script>
        </div>
      </:hero>

      <.section id="what-are-tokens" coin_side="left">
        <:coin>
          <.token_coin id="coin-what-are-tokens" class="size-28 sm:size-32" reveal />
        </:coin>
        <h2
          class="text-4xl font-bold tracking-tight opacity-0 motion-reduce:opacity-100 sm:text-5xl"
          data-reveal
        >
          What's a <span class="font-serif italic">Token</span>?
        </h2>
        <p
          class="mt-6 max-w-lg text-lg text-base-content/70 opacity-0 motion-reduce:opacity-100"
          data-reveal
        >
          A High Society Token isn't currency, and it isn't a chip you cash out at the
          door. It's your standing at the tables — a running score of how you've played,
          earned every time you sit down and every time you win. Save them, spend them,
          or just watch the balance climb.
        </p>
      </.section>

      <.section id="how-you-earn" coin_side="right" bg="bg-base-200">
        <:coin>
          <.token_coin id="coin-how-you-earn" class="size-28 sm:size-32" reveal />
        </:coin>
        <h2
          class="text-4xl font-bold tracking-tight opacity-0 motion-reduce:opacity-100 sm:text-5xl"
          data-reveal
        >
          How you <span class="font-serif italic">earn</span> them
        </h2>

        <ul class="mt-8 space-y-6">
          <li class="flex gap-4 opacity-0 motion-reduce:opacity-100" data-reveal>
            <.icon name="hero-gift" class="mt-1 size-6 shrink-0 text-amber-500" />
            <div>
              <p class="font-semibold">Every table stakes you</p>
              <p class="mt-1 text-base-content/70">
                Sit down at a game for the first time and you get a starting stake of
                Tokens to play with — no purchase necessary.
              </p>
            </div>
          </li>
          <li class="flex gap-4 opacity-0 motion-reduce:opacity-100" data-reveal>
            <.icon name="hero-sparkles" class="mt-1 size-6 shrink-0 text-amber-500" />
            <div>
              <p class="font-semibold">Winning pays out</p>
              <p class="mt-1 text-base-content/70">
                Every hand, spin, roll, and shot that goes your way credits your balance
                immediately.
              </p>
            </div>
          </li>
          <li class="flex gap-4 opacity-0 motion-reduce:opacity-100" data-reveal>
            <.icon name="hero-rectangle-stack" class="mt-1 size-6 shrink-0 text-amber-500" />
            <div>
              <p class="font-semibold">New game, new stake</p>
              <p class="mt-1 text-base-content/70">
                Blackjack, Poker, Battleship, Slots, Roulette, Zombie Attack — each one
                hands you its own starting stake the first time you take a seat.
              </p>
            </div>
          </li>
        </ul>
      </.section>

      <.section id="how-you-redeem" coin_side="left">
        <:coin>
          <.token_coin id="coin-how-you-redeem" class="size-28 sm:size-32" reveal />
        </:coin>
        <h2
          class="text-4xl font-bold tracking-tight opacity-0 motion-reduce:opacity-100 sm:text-5xl"
          data-reveal
        >
          Where they <span class="font-serif italic">go</span>
        </h2>
        <p
          class="mt-6 max-w-lg text-lg text-base-content/70 opacity-0 motion-reduce:opacity-100"
          data-reveal
        >
          Tokens have no cash value and can't be bought, sold, or withdrawn — they only
          exist inside High Society. Right now, that means keeping the game going:
          wager them, win them back, and climb the tables.
        </p>
        <p
          class="mt-4 inline-flex items-center gap-2 rounded-full border border-amber-400/40 bg-amber-400/10 px-4 py-1.5 text-sm font-semibold text-amber-600 opacity-0 motion-reduce:opacity-100 dark:text-amber-300"
          data-reveal
        >
          <.icon name="hero-shopping-bag" class="size-4" /> A Token store is coming soon
        </p>
      </.section>

      <div
        id="tokens-cta"
        phx-hook=".CtaReveal"
        class="flex flex-col items-center gap-4 px-4 py-24 text-center sm:px-6 lg:px-8"
      >
        <h2
          class="text-3xl font-bold tracking-tight opacity-0 motion-reduce:opacity-100 sm:text-4xl"
          data-reveal-cta
        >
          Ready to take a seat?
        </h2>
        <div
          class="flex flex-wrap items-center justify-center gap-3 opacity-0 motion-reduce:opacity-100"
          data-reveal-cta
        >
          <%= if @current_scope do %>
            <.link navigate={~p"/"} class="btn btn-primary">
              Browse the tables <span aria-hidden="true">&rarr;</span>
            </.link>
          <% else %>
            <.link navigate={~p"/users/register"} class="btn btn-primary">
              Create an account
            </.link>
            <.link navigate={~p"/users/log-in"} class="btn btn-ghost">
              Log in
            </.link>
          <% end %>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".CtaReveal">
          import { animate, stagger, onScroll } from "@/vendor/anime.js"

          export default {
            mounted() {
              if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
                return
              }

              this.animation = animate(this.el.querySelectorAll("[data-reveal-cta]"), {
                opacity: [0, 1],
                translateY: [16, 0],
                delay: stagger(90),
                duration: 600,
                ease: "outQuad",
                autoplay: onScroll({ target: this.el, repeat: false }),
              })
            },
            destroyed() {
              this.animation?.revert()
            }
          }
        </script>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :coin_side, :string, values: ~w(left right), default: "left"
  attr :bg, :string, default: nil
  slot :coin, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".SectionReveal"
      class={["scroll-mt-10 px-4 py-24 sm:px-6 lg:px-8", @bg]}
    >
      <div class={[
        "mx-auto grid max-w-3xl grid-cols-1 items-center gap-10 sm:grid-cols-[auto_1fr]",
        @coin_side == "right" && "sm:[&>:first-child]:order-2"
      ]}>
        <div class="flex justify-center sm:justify-start">
          {render_slot(@coin)}
        </div>
        <div>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SectionReveal">
      import { animate, stagger, onScroll } from "@/vendor/anime.js"

      export default {
        mounted() {
          if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            return
          }

          const texts = this.el.querySelectorAll("[data-reveal]")
          const coins = this.el.querySelectorAll("[data-reveal-coin]")

          this.textAnimation = animate(texts, {
            opacity: [0, 1],
            translateY: [24, 0],
            delay: stagger(90),
            duration: 600,
            ease: "outQuad",
            autoplay: onScroll({ target: this.el, repeat: false }),
          })

          this.coinAnimation = animate(coins, {
            opacity: [0, 1],
            scale: [0.4, 1],
            rotate: [-160, 0],
            duration: 800,
            // A beat after the section scrolls into view, rather than the
            // instant it does - otherwise a slow scroller only catches the
            // tail end of the coin settling into place.
            delay: 400,
            ease: "outBack",
            autoplay: onScroll({ target: this.el, repeat: false }),
          })
        },
        destroyed() {
          this.textAnimation?.revert()
          this.coinAnimation?.revert()
        }
      }
    </script>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: "size-32"
  attr :reveal, :boolean, default: false

  defp token_coin(assigns) do
    assigns = assign(assigns, :ticks, coin_ticks())

    ~H"""
    <svg
      id={@id}
      viewBox="0 0 120 120"
      class={[@class, @reveal && "opacity-0 motion-reduce:opacity-100"]}
      data-reveal-coin={@reveal}
    >
      <.coin_face id={@id} ticks={@ticks} />
    </svg>
    """
  end

  # The hero's coin needs its `phx-hook` to be a plain string literal, not a
  # runtime expression - the compiler only resolves and namespaces a
  # colocated hook name (see the `.CoinIdleSpin` script below) when it can
  # see the literal `".HookName"` at compile time, which is why this is a
  # separate component from the plain (non-hooked) `token_coin/1` above
  # rather than the same one with a conditional `phx-hook`.
  attr :id, :string, required: true
  attr :class, :string, default: "size-32"

  defp hero_token_coin(assigns) do
    assigns = assign(assigns, :ticks, coin_ticks())

    ~H"""
    <div class="[perspective:900px]">
      <div
        id={@id}
        phx-hook=".CoinIdleSpin"
        class={[
          @class,
          "relative opacity-0 [transform-style:preserve-3d] [will-change:transform] motion-reduce:opacity-100"
        ]}
      >
        <svg
          viewBox="0 0 120 120"
          class="absolute inset-0 size-full [backface-visibility:hidden] [will-change:transform]"
        >
          <.coin_face id={"#{@id}-front"} ticks={@ticks} />
        </svg>
        <svg
          viewBox="0 0 120 120"
          class="absolute inset-0 size-full [backface-visibility:hidden] [will-change:transform] [transform:rotateY(180deg)]"
        >
          <.coin_face id={"#{@id}-back"} ticks={@ticks} />
        </svg>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CoinIdleSpin">
      import { animate } from "@/vendor/anime.js"

      export default {
        mounted() {
          if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
            this.el.style.opacity = 1
            return
          }

          animate(this.el, {
            opacity: [0, 1],
            scale: [0.6, 1],
            duration: 900,
            ease: "outQuad",
            onComplete: () => {
              // A single one-way sweep, restarted from 0 on every loop
              // (not alternate), so it keeps turning the same direction
              // instead of winding back and forth.
              this.spin = animate(this.el, {
                rotateY: [0, 360],
                duration: 3200,
                loop: true,
                ease: "linear",
              })
            }
          })
        },
        destroyed() {
          this.spin?.revert()
        }
      }
    </script>
    """
  end

  attr :id, :string, required: true
  attr :ticks, :list, required: true

  defp coin_face(assigns) do
    ~H"""
    <defs>
      <linearGradient id={"#{@id}-gold"} x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="#f6d77c" />
        <stop offset=".5" stop-color="#c8a24d" />
        <stop offset="1" stop-color="#87631c" />
      </linearGradient>
    </defs>

    <circle cx="60" cy="60" r="56" fill="#111" stroke={"url(##{@id}-gold)"} stroke-width="4" />
    <circle
      cx="60"
      cy="60"
      r="46"
      fill="none"
      stroke={"url(##{@id}-gold)"}
      stroke-width="1.5"
      stroke-opacity=".4"
    />

    <g stroke={"url(##{@id}-gold)"} stroke-width="2" stroke-linecap="round" opacity=".5">
      <line :for={t <- @ticks} x1={t.x1} y1={t.y1} x2={t.x2} y2={t.y2} />
    </g>

    <foreignObject x="14" y="34" width="92" height="52">
      <div
        xmlns="http://www.w3.org/1999/xhtml"
        class="flex h-full w-full items-center justify-center font-serif text-[42px] font-bold text-[#c8a24d]"
      >
        HS
      </div>
    </foreignObject>
    """
  end

  # 20 evenly-spaced rim ticks, like the milled edge of a real coin - computed
  # once rather than hand-written, so the SVG markup above stays readable.
  defp coin_ticks(count \\ 20) do
    for i <- 0..(count - 1) do
      angle = 2 * :math.pi() * i / count

      %{
        x1: 60 + 51 * :math.cos(angle),
        y1: 60 + 51 * :math.sin(angle),
        x2: 60 + 55 * :math.cos(angle),
        y2: 60 + 55 * :math.sin(angle)
      }
    end
  end
end
