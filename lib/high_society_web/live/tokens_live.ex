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
    <%!-- 1600px rather than a tighter value: at a coin-sized element,
    a closer perspective distance visibly converges the top and bottom
    of the rim toward a vanishing point as it turns edge-on (correct
    wide-angle-lens behavior, but for a coin that's meant to read as
    small and far enough away to be flat-on to the viewer, it shows up
    as the rim looking uneven top-to-bottom rather than a uniform band).
    A longer distance flattens that convergence toward parallel,
    closer to a telephoto lens - the coin still turns in 3D, just
    without that extra, unwanted distortion on top of it. --%>
    <div class="[perspective:1600px]">
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

          this.buildRim()

          animate(this.el, {
            opacity: [0, 1],
            scale: [0.6, 1],
            duration: 900,
            ease: "outQuad",
            onComplete: () => {
              // A single one-way sweep, restarted from 0 on every loop
              // (not alternate), so it keeps turning the same direction
              // instead of winding back and forth. The rim built below is
              // a plain child of `this.el`, so it turns right along with
              // it for free - nothing here needs to know the rim exists.
              this.spin = animate(this.el, {
                rotateY: [0, 360],
                duration: 3200,
                loop: true,
                ease: "linear",
              })
            }
          })
        },

        // The coin's rim, giving the spin actual depth instead of a flat
        // image just narrowing to nothing edge-on. Three earlier versions
        // of this each got the geometry wrong in a different way:
        //
        //   1. A single flat plane rotated in place (no `translateZ`) drew
        //      a bar through the *center* of the coin at every angle
        //      instead of its boundary - with no outward push, a rotated
        //      plane just turns about the coin's own central axis. Opacity
        //      tricks on top of that (a hard keyframe blink, then a smooth
        //      `sin`-driven fade) only ever changed how visible the
        //      misplaced bar was, never where it appeared.
        //   2. A ring of strips placed with `rotateY(angle)
        //      translateZ(radius)` per strip - the standard recipe for a
        //      CSS "carousel" - looked like a solid wooden barrel/fluted
        //      column from any angle, including face-on. That recipe faces
        //      each strip *outward*, like carousel items facing the people
        //      walking around them, which is the wrong shape entirely: a
        //      coin's rim should be invisible (edge-on to the viewer) at
        //      rest, from every angle around it, not facing outward.
        //
        // The difference is which way each strip's *normal* points before
        // the parent's own spin is applied. A real rim patch at angle φ
        // around the coin's face has a normal of (cos φ, sin φ, 0) - it
        // has no Z-component at all, which is exactly why the whole rim is
        // invisible when the coin is face-on (p=0): every patch is
        // edge-on to the viewer simultaneously, regardless of φ. Composed
        // CSS rotations (`rotateY(φ) translateZ(r)`) don't produce that -
        // they're the carousel case, normal (sin φ, 0, cos φ), which
        // faces the viewer near φ=0 rather than staying edge-on. Rather
        // than fight CSS's rotation-order semantics again, each strip's
        // final orientation and position is written directly as a
        // `matrix3d`, built from exactly the three basis vectors this
        // rim actually needs:
        //   - local X (the strip's own width, tangent to the ring) -> (-sin φ, cos φ, 0)
        //   - local Y (the strip's own height, the coin's thickness)  -> (0, 0, 1)
        //   - local Z (the strip's face normal)                      -> (cos φ, sin φ, 0)
        //   - translation, the strip's position on the ring           -> (R cos φ, R sin φ, 0)
        // Every strip is still a plain child of `this.el`, so the whole
        // rim turns for free the instant the parent's own `rotateY` does -
        // nested transforms compose regardless of how the inner one was
        // built. `backfaceVisibility: hidden` per strip then lets the
        // browser's real 3D compositing decide which ones face the viewer
        // at any given moment, the same way it already does for the two
        // coin faces.
        buildRim() {
          const size = this.el.getBoundingClientRect().width
          if (!size) return

          const radius = size * 0.467
          const thickness = size * 0.12
          const stripCount = 64
          const width = ((2 * Math.PI * radius) / stripCount) * 1.3

          // Pulled in a hair short of the true radius - at that exact
          // radius, the rim's outer edge and the coin face's own edge
          // sit at the *same* depth (both at Z=0, the face by never
          // getting a translateZ of its own, the rim because a ring
          // traces the face's boundary circle, Z=0 too) with nothing to
          // separate them but floating-point luck once perspective and
          // rotation are both in play - a coin-flip coin toss for which
          // one the renderer draws on top at their shared seam, frame to
          // frame. Nudging the rim a couple pixels inward breaks that tie
          // in the rim's favor consistently, well under a pixel's worth
          // of visual difference in radius.
          const inset = radius - Math.min(2, radius * 0.03)

          for (let i = 0; i < stripCount; i++) {
            const phi = (2 * Math.PI * i) / stripCount
            const cos = Math.cos(phi)
            const sin = Math.sin(phi)
            const strip = document.createElement("div")

            strip.style.position = "absolute"
            strip.style.left = "50%"
            strip.style.top = "50%"
            strip.style.width = `${width}px`
            strip.style.height = `${thickness}px`
            strip.style.marginLeft = `${-width / 2}px`
            strip.style.marginTop = `${-thickness / 2}px`
            strip.style.background = "linear-gradient(90deg, #87631c, #f6d77c 50%, #87631c)"
            strip.style.backfaceVisibility = "hidden"
            strip.style.transform = `matrix3d(
              ${-sin}, ${cos}, 0, 0,
              0, 0, 1, 0,
              ${cos}, ${sin}, 0, 0,
              ${inset * cos}, ${inset * sin}, 0, 1
            )`

            this.el.appendChild(strip)
          }
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

  # TRIAL: swapped in the new `hs-token.png` artwork in place of the
  # hand-drawn rim-ticks/gradient/"HS" SVG face, to compare side by side -
  # revert to the SVG version above (in git history) if it's not a clear
  # improvement.
  defp coin_face(assigns) do
    ~H"""
    <image href="/images/hs-token.png" x="0" y="0" width="120" height="120" />
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
