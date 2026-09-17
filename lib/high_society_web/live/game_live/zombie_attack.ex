defmodule HighSocietyWeb.GameLive.ZombieAttack do
  @moduledoc """
  Zombie Attack: place defenders across the lawn and survive 5 waves.

  The real-time match (zombie movement, placement, combat) is simulated
  entirely client-side on a canvas via the `.GameCanvas` colocated hook -
  this module only ever sees two checkpoints back from it, `wave_cleared`
  and `game_over`. See `HighSociety.Games.ZombieAttack`'s moduledoc for why.

  On mount with an already-in-progress game (e.g. a mid-match page
  refresh), `match_started` is pushed again so the canvas can resume -
  the client's local defenders/placements are lost (nothing about them is
  persisted, by design), but it resumes at the correct wave rather than
  replaying already-cleared ones, via the `wave_reached` in the payload.
  """
  use HighSocietyWeb, :live_view

  alias HighSociety.Accounts
  alias HighSociety.Accounts.Scope
  alias HighSociety.Games.ZombieAttack
  alias HighSociety.Games.ZombieAttackContext
  alias HighSociety.Tokens

  @wager_options [100, 500, 1_000, 2_500, 5_000, 10_000, 25_000]

  @impl true
  def mount(_params, _session, socket) do
    game = ZombieAttackContext.get_active_zombie_attack_game(socket.assigns.current_scope)

    socket =
      assign(socket,
        page_title: "Zombie Attack",
        game: game,
        wager_options: @wager_options,
        wave_count: ZombieAttack.wave_count(),
        defender_specs: ZombieAttack.defender_specs(),
        defender_order: ZombieAttack.defender_order(),
        error: nil
      )

    socket =
      if connected?(socket) && game do
        push_event(socket, "match_started", match_started_payload(game))
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("start_game", %{"wager" => wager_str}, socket) do
    with {wager, ""} <- Integer.parse(wager_str),
         true <- wager > 0,
         {:ok, game} <-
           ZombieAttackContext.start_zombie_attack_game(socket.assigns.current_scope, wager) do
      user = Accounts.get_user!(socket.assigns.current_scope.user.id)

      socket =
        socket
        |> assign(game: game, error: nil, current_scope: Scope.for_user(user))
        |> push_event("match_started", match_started_payload(game))

      {:noreply, socket}
    else
      {:error, :insufficient_funds} ->
        {:noreply, assign(socket, error: "You don't have enough balance for that wager.")}

      {:error, :wager_too_high} ->
        {:noreply,
         assign(socket,
           error: "The max wager is #{Tokens.format(ZombieAttack.max_wager())} Tokens."
         )}

      _ ->
        {:noreply, assign(socket, error: "Enter a valid wager.")}
    end
  end

  def handle_event("wave_cleared", %{"wave" => wave}, socket) when is_integer(wave) do
    case ZombieAttackContext.report_wave_cleared(
           socket.assigns.current_scope,
           socket.assigns.game,
           wave
         ) do
      {:ok, game, user} ->
        socket = assign(socket, game: game, current_scope: Scope.for_user(user))

        socket =
          if game.status == "won" do
            push_event(socket, "play_sounds", %{sounds: ["game-over", "you-win"]})
          else
            socket
          end

        {:noreply, socket}

      {:error, :invalid_checkpoint} ->
        {:noreply, socket}
    end
  end

  def handle_event("game_over", _params, socket) do
    {:ok, game, user} =
      ZombieAttackContext.report_game_over(socket.assigns.current_scope, socket.assigns.game)

    socket =
      socket
      |> assign(game: game, current_scope: Scope.for_user(user))
      |> push_event("play_sounds", %{sounds: ["game-over", "you-lose"]})

    {:noreply, socket}
  end

  def handle_event("play_again", _params, socket) do
    {:noreply, assign(socket, game: nil, error: nil)}
  end

  def handle_event("claim_zombie_attack_tokens", _params, socket) do
    case Accounts.claim_zombie_attack_tokens(socket.assigns.current_scope.user) do
      {:ok, user} -> {:noreply, assign(socket, current_scope: Scope.for_user(user))}
      {:error, :already_claimed} -> {:noreply, socket}
    end
  end

  defp match_started_payload(game) do
    %{
      wave_schedule: game.wave_schedule,
      wave_reached: game.wave_reached,
      lanes: ZombieAttack.lanes(),
      columns: ZombieAttack.columns(),
      defender_specs: ZombieAttack.defender_specs(),
      zombie_specs: ZombieAttack.zombie_specs()
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="zombie-attack-screen" class="mx-auto max-w-4xl" phx-hook=".SoundEffects">
        <div class="flex items-center justify-between">
          <div>
            <.link navigate={~p"/#games"} class="text-sm text-base-content/60 hover:text-base-content">
              &larr; All games
            </.link>
            <h1 class="mt-1 text-3xl font-bold tracking-tight">Zombie Attack</h1>
          </div>
          <div class="flex items-center gap-3">
            <div class="text-right">
              <div class="text-xs font-medium uppercase tracking-wide text-base-content/50">
                Balance
              </div>
              <.token_balance amount={@current_scope.user.tokens_balance} />
            </div>
            <button
              :if={is_nil(@current_scope.user.claimed_zombie_attack_tokens_at)}
              id="claim-zombie-attack-tokens-button"
              type="button"
              phx-click="claim_zombie_attack_tokens"
              class="btn btn-success btn-sm animate-pulse"
            >
              Claim {Tokens.format(Accounts.zombie_attack_starting_token_amount())} Tokens
            </button>
            <button
              id="sound-toggle-button"
              type="button"
              phx-hook=".SoundToggle"
              class="btn btn-ghost btn-sm btn-circle"
              aria-label="Toggle sound"
              aria-pressed="true"
            >
              <.icon name="hero-speaker-wave" class="size-4 sound-on-icon" />
              <.icon name="hero-speaker-x-mark" class="size-4 sound-off-icon hidden" />
            </button>
          </div>
        </div>

        <p :if={@error} class="mt-4 alert alert-error text-sm">{@error}</p>

        <div :if={is_nil(@game)} class="mt-10 flex flex-col items-center gap-4">
          <p class="text-base-content/70">
            Choose a wager. Survive all {@wave_count} waves for the full payout.
          </p>
          <form phx-submit="start_game" class="flex items-center gap-2">
            <select name="wager" class="select select-bordered">
              <option :for={amount <- @wager_options} value={amount}>
                {Tokens.format(amount)} Tokens
              </option>
            </select>
            <button type="submit" class="btn btn-primary">Start game</button>
          </form>
        </div>

        <div
          :if={@game && @game.status == "in_progress"}
          class="mt-8 flex flex-col items-center gap-4"
        >
          <div
            id="zombie-attack-canvas-wrap"
            phx-hook=".GameCanvas"
            class="relative flex flex-col items-center gap-3"
          >
            <div
              id="zombie-how-to-play"
              class="absolute inset-0 z-10 hidden flex-col items-center justify-center gap-4 rounded-md bg-base-100/95 p-6 text-center backdrop-blur-sm"
            >
              <h2 class="text-xl font-bold">How to play</h2>
              <ul class="max-w-sm space-y-2 text-left text-sm text-base-content/80">
                <li>
                  <strong class="text-base-content">Objective:</strong>
                  survive all {@wave_count} waves. If a single zombie reaches your side, the run ends immediately.
                </li>
                <li>
                  <strong class="text-base-content">Placing defenders:</strong>
                  click a defender below, then click a lane on the field to place it.
                </li>
                <li>
                  <strong class="text-base-content">Supplies</strong>
                  build up automatically and pay for defenders.
                </li>
                <li :for={type <- @defender_order}>
                  <% spec = @defender_specs[type] %>
                  <strong class="text-base-content">{spec.name} ({spec.cost} supplies):</strong>
                  {defender_tip(type)}
                </li>
              </ul>
              <button type="button" id="zombie-how-to-play-dismiss" class="btn btn-primary mt-6">
                Got it — let's go
              </button>
            </div>

            <div class="flex w-full max-w-[640px] items-center justify-between text-sm">
              <div id="zombie-hud-status" class="font-semibold"></div>
              <div class="flex items-center gap-3">
                <div id="zombie-hud-supplies" class="font-mono text-base-content/70"></div>
                <button
                  type="button"
                  id="zombie-how-to-play-reopen"
                  class="btn btn-ghost btn-xs btn-circle"
                  aria-label="How to play"
                >
                  <.icon name="hero-question-mark-circle" class="size-4" />
                </button>
              </div>
            </div>
            <canvas
              id="zombie-canvas"
              width="640"
              height="320"
              class="h-auto max-w-full rounded-md border border-base-300 bg-base-200"
            ></canvas>
            <div class="flex gap-2">
              <div
                :for={type <- @defender_order}
                class="tooltip"
                data-tip={defender_tip(type)}
              >
                <% spec = @defender_specs[type] %>
                <button
                  type="button"
                  id={"zombie-palette-#{type}"}
                  data-defender-type={type}
                  class="btn btn-sm btn-outline"
                >
                  {spec.name} ({spec.cost} supplies)
                </button>
              </div>
            </div>
          </div>
        </div>

        <div :if={@game && @game.status == "won"} class="mt-10 text-center">
          <p class="text-2xl font-bold text-success">You held the line! 🎉</p>
          <p class="text-base-content/70">You won {Tokens.format(@game.payout)} Tokens.</p>
          <button type="button" phx-click="play_again" class="btn btn-primary mt-4">
            Play again
          </button>
        </div>

        <div :if={@game && @game.status == "lost"} class="mt-10 text-center">
          <p class="text-2xl font-bold text-error">The house has fallen.</p>
          <p class="text-base-content/70">
            You cleared {@game.wave_reached}/{@wave_count} waves and won {Tokens.format(@game.payout)} Tokens.
          </p>
          <button type="button" phx-click="play_again" class="btn btn-primary mt-4">
            Play again
          </button>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SoundToggle">
        export default {
          mounted() {
            this.storageKey = "high_society:sound_muted"
            this.onIcon = this.el.querySelector(".sound-on-icon")
            this.offIcon = this.el.querySelector(".sound-off-icon")
            this.applyState(this.isMuted())

            this.el.addEventListener("click", () => {
              const muted = !this.isMuted()
              localStorage.setItem(this.storageKey, muted ? "true" : "false")
              this.applyState(muted)
            })
          },
          isMuted() {
            return localStorage.getItem(this.storageKey) === "true"
          },
          applyState(muted) {
            this.onIcon.classList.toggle("hidden", muted)
            this.offIcon.classList.toggle("hidden", !muted)
            this.el.setAttribute("aria-pressed", muted ? "false" : "true")
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SoundEffects">
        export default {
          mounted() {
            this.queue = []
            this.playing = false

            // Queued and played one at a time - the round-ending stinger
            // ("game-over") then the outcome-specific one ("you-win" /
            // "you-lose") read as a sequence rather than overlapping.
            this.handleEvent("play_sounds", ({sounds}) => {
              if (localStorage.getItem("high_society:sound_muted") === "true") return

              this.queue.push(...sounds)
              this.playNext()
            })
          },
          playNext() {
            if (this.playing) return

            const name = this.queue.shift()
            if (!name) return

            const audio = new Audio(`/audio/zombie-attack/${name}.aac`)
            this.playing = true

            const advance = () => {
              this.playing = false
              this.playNext()
            }

            audio.addEventListener("ended", advance)
            audio.addEventListener("error", advance)
            audio.play().catch(advance)
          }
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".GameCanvas">
        // Tuning constants for the client-only simulation. These are
        // presentation/feel choices, not economy-affecting - the payout
        // table lives in Elixir (`HighSociety.Games.ZombieAttack`) and
        // never sees any of this.
        const STARTING_SUPPLIES = 130
        const SUPPLIES_PER_SEC = 10
        const PREP_MS = 8000
        const BREAK_MS = 3000
        const SPEED_DIVISOR = 20 // converts a zombie spec's `speed` into columns/sec
        const ZOMBIE_MELEE_DPS = 10
        const COUNTDOWN_MS = 3000 // how much of a prep phase gets the big on-canvas countdown
        const GO_FLASH_MS = 700 // how long the "GO!" flash lingers once a wave starts

        // Zombie spritesheets: 128x128 frames, walk/attack looping,
        // dead playing once. Frame counts come from the CraftPix pack
        // (see priv/static/images/zombie-attack/LICENSE.txt) - fixed
        // here rather than measured at runtime since they're a stable
        // property of the specific asset files.
        const ZOMBIE_FRAME_SIZE = 128
        const ZOMBIE_ANIM = {
          walk: { frames: 10, frameMs: 90 },
          attack: { frames: 5, frameMs: 100 },
          dead: { frames: 5, frameMs: 90 }
        }

        // Turret shoot-cycle frames (CraftPix "Merge Turrets" pack, tiers
        // T1/T13 - see LICENSE.txt). 15 frames each; frame 0 doubles as the
        // idle pose. Timed to finish just inside the 700ms fire_rate_ms
        // both defender types currently share, so the recoil settles
        // before the next shot.
        const TURRET_ANIM = { frames: 15, frameMs: 45 }
        const MUZZLE_FLASH_ANIM = { frames: 15, frameMs: 20 }
        const EXPLOSION_ANIM = { frames: 19, frameMs: 25 }
        const PROJECTILE_TRAVEL_MS = 140

        export default {
          mounted() {
            this.canvas = this.el.querySelector("#zombie-canvas")
            this.ctx = this.canvas.getContext("2d")
            this.statusEl = this.el.querySelector("#zombie-hud-status")
            this.suppliesEl = this.el.querySelector("#zombie-hud-supplies")
            this.introEl = this.el.querySelector("#zombie-how-to-play")
            this.paletteButtons = this.el.querySelectorAll("[data-defender-type]")
            this.selectedType = null
            this.game = null
            this.rafId = null
            this.reportedWaves = new Set()
            this.reportedGameOver = false

            this.paletteButtons.forEach(btn => {
              btn.addEventListener("click", () => {
                this.selectedType = btn.dataset.defenderType
                this.paletteButtons.forEach(b => b.classList.toggle("btn-primary", b === btn))
              })
            })

            this.canvas.addEventListener("click", e => this.handleCanvasClick(e))

            this.el.querySelector("#zombie-how-to-play-dismiss")
              .addEventListener("click", () => this.dismissIntro())
            this.el.querySelector("#zombie-how-to-play-reopen")
              .addEventListener("click", () => this.introEl.classList.remove("hidden"))

            this.sprites = {}
            const spriteNames = [
              "ground-grass", "defender-blocker",
              "zombie-walker-walk", "zombie-walker-attack", "zombie-walker-dead",
              "zombie-armored-walk", "zombie-armored-attack", "zombie-armored-dead"
            ]
            for (const name of spriteNames) {
              const img = new Image()
              img.src = `/images/zombie-attack/${name}.png`
              this.sprites[name] = img
            }

            const frameSetNames = {
              "turret-shooter": TURRET_ANIM.frames,
              "turret-cannon": TURRET_ANIM.frames,
              "muzzle-flash": MUZZLE_FLASH_ANIM.frames,
              explosion: EXPLOSION_ANIM.frames
            }
            this.frameSets = {}
            for (const [name, count] of Object.entries(frameSetNames)) {
              this.frameSets[name] = Array.from({ length: count }, (_, i) => {
                const img = new Image()
                img.src = `/images/zombie-attack/${name}-${String(i).padStart(2, "0")}.png`
                return img
              })
            }

            this.projectileSprite = new Image()
            this.projectileSprite.src = "/images/zombie-attack/projectile.png"

            this.music = new Audio("/audio/zombie-attack/zombie-attack-music.mp3")
            this.music.loop = true
            this.music.volume = 0.35

            this.handleEvent("match_started", payload => this.startMatch(payload))

            this.draw()
            this.rafId = requestAnimationFrame(t => this.tick(t))
          },

          destroyed() {
            if (this.rafId) cancelAnimationFrame(this.rafId)
            this.music.pause()
          },

          isMuted() {
            return localStorage.getItem("high_society:sound_muted") === "true"
          },

          playFx(name) {
            if (this.isMuted()) return
            const audio = new Audio(`/audio/zombie-attack/${name}.aac`)
            audio.volume = 0.6
            audio.play().catch(() => {})
          },

          // Keeps the background music in sync with the mute toggle and the
          // match's own lifecycle every frame, rather than only checking
          // once when the match starts - so muting mid-match (or a match
          // ending) actually stops it, instead of just blocking future fx.
          syncMusic() {
            const active = this.game && (this.game.status === "prep" || this.game.status === "wave")

            if (active && !this.isMuted()) {
              if (this.music.paused) this.music.play().catch(() => {})
            } else if (!this.music.paused) {
              this.music.pause()
            }
          },

          startMatch(payload) {
            const cellSize = this.canvas.width / payload.columns
            const now = performance.now()
            const seenIntro = localStorage.getItem("high_society:zombie_attack_seen_intro") === "true"

            this.reportedWaves = new Set()
            this.reportedGameOver = false
            this.music.currentTime = 0

            this.game = {
              lanes: payload.lanes,
              columns: payload.columns,
              cellSize,
              waveSchedule: payload.wave_schedule,
              defenderSpecs: payload.defender_specs,
              zombieSpecs: payload.zombie_specs,
              waveIndex: payload.wave_reached,
              supplies: STARTING_SUPPLIES,
              defenders: [],
              zombies: [],
              projectiles: [],
              bursts: [],
              // First-time players get an "intro" pause instead of going
              // straight to "prep" - the countdown to wave 1 doesn't start
              // ticking until they've dismissed the how-to-play panel, so
              // reading it doesn't eat into their prep time.
              status: seenIntro ? "prep" : "intro",
              phaseEndsAt: seenIntro ? now + PREP_MS : null,
              lastFrameAt: now
            }

            this.introEl.classList.toggle("hidden", seenIntro)
          },

          dismissIntro() {
            localStorage.setItem("high_society:zombie_attack_seen_intro", "true")
            this.introEl.classList.add("hidden")

            if (this.game && this.game.status === "intro") {
              this.game.status = "prep"
              this.game.phaseEndsAt = performance.now() + PREP_MS
            }
          },

          handleCanvasClick(e) {
            if (!this.selectedType || !this.game) return
            if (this.game.status === "won" || this.game.status === "lost") return
            if (this.game.status === "intro") return

            const rect = this.canvas.getBoundingClientRect()
            const x = (e.clientX - rect.left) * (this.canvas.width / rect.width)
            const y = (e.clientY - rect.top) * (this.canvas.height / rect.height)
            const laneHeight = this.canvas.height / this.game.lanes
            const col = Math.floor(x / this.game.cellSize)
            const lane = Math.floor(y / laneHeight)

            this.placeDefender(lane, col)
          },

          placeDefender(lane, col) {
            const g = this.game
            const spec = g.defenderSpecs[this.selectedType]
            if (!spec) return
            if (g.supplies < spec.cost) return
            if (g.defenders.some(d => d.lane === lane && d.col === col)) return

            g.supplies -= spec.cost
            g.defenders.push({
              lane,
              col,
              type: this.selectedType,
              hp: spec.hp,
              maxHp: spec.hp,
              cooldownMs: 0,
              lastShotAt: -Infinity
            })
          },

          beginWave(now) {
            const g = this.game
            const wave = g.waveSchedule[g.waveIndex]
            g.spawnQueue = wave.spawns.map(s => ({ ...s, spawnAt: now + s.spawn_at_ms }))
            g.status = "wave"
            g.waveStartedAt = now
          },

          reportWaveCleared(waveNumber) {
            if (this.reportedWaves.has(waveNumber)) return
            this.reportedWaves.add(waveNumber)
            this.pushEvent("wave_cleared", { wave: waveNumber })
          },

          reportGameOver() {
            if (this.reportedGameOver) return
            this.reportedGameOver = true
            this.pushEvent("game_over", {})
          },

          update(dt, now) {
            const g = this.game
            if (g.status === "intro") return

            g.supplies += SUPPLIES_PER_SEC * dt

            if (g.status === "prep") {
              if (now >= g.phaseEndsAt) this.beginWave(now)
              return
            }

            while (g.spawnQueue.length > 0 && now >= g.spawnQueue[0].spawnAt) {
              const spawn = g.spawnQueue.shift()
              const spec = g.zombieSpecs[spawn.zombie_type]
              g.zombies.push({
                lane: spawn.lane,
                type: spawn.zombie_type,
                pos: g.columns,
                hp: spec.hp,
                maxHp: spec.hp,
                speed: spec.speed / SPEED_DIVISOR,
                blockedBy: null,
                animState: "walk",
                stateEnteredAt: now
              })
              this.playFx("zombie-growl")
            }

            for (const z of g.zombies) {
              if (z.animState === "dying") continue

              if (z.hp <= 0) {
                z.animState = "dying"
                z.stateEnteredAt = now
                z.blockedBy = null
                continue
              }

              if (z.blockedBy) {
                if (z.blockedBy.hp <= 0) {
                  z.blockedBy = null
                } else {
                  z.blockedBy.hp -= ZOMBIE_MELEE_DPS * dt
                  if (z.animState !== "attack") {
                    z.animState = "attack"
                    z.stateEnteredAt = now
                  }
                  continue
                }
              }

              if (z.animState !== "walk") {
                z.animState = "walk"
                z.stateEnteredAt = now
              }

              const targetX = z.pos - z.speed * dt
              const blocker = g.defenders
                .filter(d => d.lane === z.lane && d.col < z.pos && d.hp > 0)
                .sort((a, b) => b.col - a.col)[0]

              if (blocker && blocker.col + 1 >= targetX) {
                z.pos = blocker.col + 1
                z.blockedBy = blocker
                z.animState = "attack"
                z.stateEnteredAt = now
                this.playFx("zombie-attack-whoosh")
              } else {
                z.pos = targetX
              }
            }

            // Dying zombies linger through their death animation instead of
            // vanishing instantly - also means a wave isn't declared clear
            // until the last kill has finished playing out.
            const deathAnimMs = ZOMBIE_ANIM.dead.frames * ZOMBIE_ANIM.dead.frameMs
            g.zombies = g.zombies.filter(
              z => z.animState !== "dying" || now - z.stateEnteredAt < deathAnimMs
            )
            g.defenders = g.defenders.filter(d => d.hp > 0)

            if (g.zombies.some(z => z.animState !== "dying" && z.pos <= 0)) {
              g.status = "lost"
              this.reportGameOver()
              return
            }

            const laneHeight = this.canvas.height / g.lanes

            for (const d of g.defenders) {
              const spec = g.defenderSpecs[d.type]
              if (!spec.damage || !spec.fire_rate_ms) continue

              d.cooldownMs -= dt * 1000
              if (d.cooldownMs > 0) continue

              const target = g.zombies
                .filter(
                  z =>
                    z.animState !== "dying" &&
                    z.lane === d.lane &&
                    z.pos >= d.col &&
                    z.pos <= d.col + spec.range
                )
                .sort((a, b) => a.pos - b.pos)[0]

              if (target) {
                d.cooldownMs = spec.fire_rate_ms
                d.lastShotAt = now

                const fromX = d.col * g.cellSize + g.cellSize / 2
                const fromY = d.lane * laneHeight + laneHeight / 2
                g.projectiles.push({
                  fromX,
                  fromY,
                  toX: target.pos * g.cellSize,
                  toY: target.lane * laneHeight + laneHeight / 2,
                  startedAt: now,
                  damage: spec.damage,
                  target
                })
                g.bursts.push({ kind: "muzzle-flash", x: fromX, y: fromY, startedAt: now })
              }
            }

            for (const p of g.projectiles) {
              if (p.hit) continue

              const t = Math.min(1, (now - p.startedAt) / PROJECTILE_TRAVEL_MS)
              if (t < 1) continue

              p.hit = true
              // The target may already be mid-death-animation from another
              // projectile that landed first - still worth a hit spark at
              // the impact point, just no further damage to apply.
              if (p.target.animState !== "dying") p.target.hp -= p.damage

              // Impact point is where the projectile visually arrives
              // (its target's position when fired), not the target's
              // current position - it may have moved since.
              g.bursts.push({ kind: "explosion", x: p.toX, y: p.toY, startedAt: now })
            }
            g.projectiles = g.projectiles.filter(p => !p.hit)

            if (g.spawnQueue.length === 0 && g.zombies.length === 0) {
              const clearedWave = g.waveIndex + 1

              if (g.waveIndex >= g.waveSchedule.length - 1) {
                g.status = "won"
              } else {
                g.waveIndex += 1
                g.status = "prep"
                g.phaseEndsAt = now + BREAK_MS
              }

              this.reportWaveCleared(clearedWave)
            }
          },

          tick(now) {
            const g = this.game
            if (g && g.status !== "won" && g.status !== "lost") {
              const dt = Math.min((now - g.lastFrameAt) / 1000, 0.1)
              g.lastFrameAt = now
              this.update(dt, now)
            }

            this.updateHud()
            this.draw()
            this.syncMusic()
            this.rafId = requestAnimationFrame(t => this.tick(t))
          },

          updateHud() {
            const g = this.game
            if (!g) {
              this.statusEl.textContent = ""
              this.suppliesEl.textContent = ""
              return
            }

            this.suppliesEl.textContent = `Supplies: ${Math.floor(g.supplies)}`
            const waveNum = Math.min(g.waveIndex + 1, g.waveSchedule.length)

            if (g.status === "intro") {
              this.statusEl.textContent = "Read the guide to begin"
            } else if (g.status === "prep") {
              const secs = Math.max(0, Math.ceil((g.phaseEndsAt - performance.now()) / 1000))
              this.statusEl.textContent = `Wave ${waveNum} starts in ${secs}s`
            } else if (g.status === "wave") {
              this.statusEl.textContent = `Wave ${waveNum} in progress`
            } else if (g.status === "won") {
              this.statusEl.textContent = "You held the line!"
            } else if (g.status === "lost") {
              this.statusEl.textContent = "The house has fallen."
            }
          },

          spriteReady(name) {
            const img = this.sprites[name]
            return !!(img && img.complete && img.naturalWidth > 0)
          },

          draw() {
            const ctx = this.ctx
            const columns = this.game?.columns ?? 8
            const lanes = this.game?.lanes ?? 4
            const cellSize = this.canvas.width / columns
            const laneHeight = this.canvas.height / lanes

            if (this.spriteReady("ground-grass")) {
              const ground = this.sprites["ground-grass"]
              for (let c = 0; c < columns; c++) {
                for (let l = 0; l < lanes; l++) {
                  ctx.drawImage(ground, c * cellSize, l * laneHeight, cellSize, laneHeight)
                }
              }
            } else {
              ctx.fillStyle = "#1b3a1b"
              ctx.fillRect(0, 0, this.canvas.width, this.canvas.height)
            }

            // A visual cue for orientation: the house (what you're
            // defending) is on the left, zombies spawn off the right edge
            // and walk toward it.
            const spawnZoneWidth = cellSize * 0.6
            const spawnGradient = ctx.createLinearGradient(
              this.canvas.width - spawnZoneWidth, 0, this.canvas.width, 0
            )
            spawnGradient.addColorStop(0, "rgba(127,29,29,0)")
            spawnGradient.addColorStop(1, "rgba(127,29,29,0.5)")
            ctx.fillStyle = spawnGradient
            ctx.fillRect(this.canvas.width - spawnZoneWidth, 0, spawnZoneWidth, this.canvas.height)

            this.drawHouseIcon(laneHeight * lanes)

            ctx.save()
            ctx.translate(30, this.canvas.height / 2)
            ctx.rotate(-Math.PI / 2)
            ctx.fillStyle = "rgba(255,255,255,0.55)"
            ctx.font = "bold 11px sans-serif"
            ctx.textAlign = "center"
            ctx.fillText("HOUSE - DEFEND THIS SIDE", 0, 4)
            ctx.restore()

            ctx.fillStyle = "rgba(255,255,255,0.55)"
            ctx.font = "bold 11px sans-serif"
            ctx.textAlign = "right"
            ctx.fillText("ZOMBIES ENTER →", this.canvas.width - 4, 14)

            ctx.strokeStyle = "rgba(255,255,255,0.15)"
            ctx.lineWidth = 1
            for (let c = 1; c < columns; c++) {
              ctx.beginPath()
              ctx.moveTo(c * cellSize, 0)
              ctx.lineTo(c * cellSize, this.canvas.height)
              ctx.stroke()
            }
            for (let l = 1; l < lanes; l++) {
              ctx.beginPath()
              ctx.moveTo(0, l * laneHeight)
              ctx.lineTo(this.canvas.width, l * laneHeight)
              ctx.stroke()
            }

            if (!this.game) return
            const g = this.game
            const now = performance.now()

            for (const d of g.defenders) {
              const cx = d.col * cellSize + cellSize / 2
              const cy = d.lane * laneHeight + laneHeight / 2

              if (d.type === "blocker") {
                const size = cellSize * 0.7
                if (this.spriteReady("defender-blocker")) {
                  ctx.drawImage(this.sprites["defender-blocker"], cx - size / 2, cy - size / 2, size, size)
                } else {
                  ctx.fillStyle = "#9ca3af"
                  ctx.fillRect(cx - size / 2, cy - size / 2, size, size)
                }
                this.drawHpBar(cx, cy - size / 2 - 8, size, d.hp, d.maxHp)
                continue
              }

              // Shooter/cannon: an idle->shoot cycle (CraftPix "Merge
              // Turrets" pack) - frame 0 is the resting pose, and firing
              // (see the projectile-spawn code above) resets lastShotAt so
              // the recoil animation plays out here.
              const frames = this.frameSets[d.type === "cannon" ? "turret-cannon" : "turret-shooter"]
              const sinceShot = now - d.lastShotAt
              const cycleMs = TURRET_ANIM.frames * TURRET_ANIM.frameMs
              const frameIndex =
                sinceShot < cycleMs ? Math.min(TURRET_ANIM.frames - 1, Math.floor(sinceShot / TURRET_ANIM.frameMs)) : 0
              const frame = frames && frames[frameIndex]

              const drawHeight = cellSize * 0.85
              let drawWidth = drawHeight

              if (frame && frame.complete && frame.naturalWidth > 0) {
                drawWidth = drawHeight * (frame.naturalWidth / frame.naturalHeight)
                ctx.save()
                ctx.translate(cx, cy)
                ctx.rotate(Math.PI / 2) // sprite's default facing is up; turrets face right, toward the zombies
                ctx.drawImage(frame, -drawWidth / 2, -drawHeight / 2, drawWidth, drawHeight)
                ctx.restore()
              } else {
                const size = cellSize * 0.7
                ctx.fillStyle = "#3b82f6"
                ctx.fillRect(cx - size / 2, cy - size / 2, size, size)
              }

              // After the 90deg rotation above, the sprite's on-screen
              // vertical extent is its (pre-rotation) width, not height.
              this.drawHpBar(cx, cy - drawWidth / 2 - 8, cellSize * 0.7, d.hp, d.maxHp)
            }

            for (const z of g.zombies) {
              const cx = z.pos * cellSize
              const laneBottom = (z.lane + 1) * laneHeight
              const animKey = z.animState === "dying" ? "dead" : z.animState
              const spriteName = `zombie-${z.type}-${animKey}`
              const anim = ZOMBIE_ANIM[animKey]
              const elapsed = now - z.stateEnteredAt
              const frameIndex =
                animKey === "dead"
                  ? Math.min(anim.frames - 1, Math.floor(elapsed / anim.frameMs))
                  : Math.floor(elapsed / anim.frameMs) % anim.frames

              // Bigger draw box than the lane is tall - the source frames
              // have a lot of transparent headroom above the character
              // (see LICENSE.txt), and armored zombies are drawn a touch
              // larger still to read as tougher.
              const drawSize = laneHeight * (z.type === "armored" ? 1.35 : 1.15)

              if (this.spriteReady(spriteName)) {
                ctx.save()
                ctx.translate(cx, laneBottom)
                ctx.scale(-1, 1) // sprite's default facing is right; zombies walk left
                ctx.drawImage(
                  this.sprites[spriteName],
                  frameIndex * ZOMBIE_FRAME_SIZE, 0, ZOMBIE_FRAME_SIZE, ZOMBIE_FRAME_SIZE,
                  -drawSize / 2, -drawSize, drawSize, drawSize
                )
                ctx.restore()
              } else {
                const cy = laneBottom - laneHeight / 2
                ctx.beginPath()
                ctx.fillStyle = z.type === "armored" ? "#7f1d1d" : "#16a34a"
                ctx.arc(cx, cy, cellSize * 0.3, 0, Math.PI * 2)
                ctx.fill()
              }

              if (z.animState !== "dying") {
                this.drawHpBar(cx, laneBottom - drawSize * 0.85, cellSize * 0.6, z.hp, z.maxHp)
              }
            }

            for (const p of g.projectiles) {
              const t = Math.min(1, (now - p.startedAt) / PROJECTILE_TRAVEL_MS)
              const px = p.fromX + (p.toX - p.fromX) * t
              const py = p.fromY + (p.toY - p.fromY) * t
              const projSize = cellSize * 0.22

              if (this.projectileSprite.complete && this.projectileSprite.naturalWidth > 0) {
                ctx.drawImage(this.projectileSprite, px - projSize / 2, py - projSize / 2, projSize, projSize)
              } else {
                ctx.beginPath()
                ctx.fillStyle = "#fde047"
                ctx.arc(px, py, 3, 0, Math.PI * 2)
                ctx.fill()
              }
            }

            g.bursts = g.bursts.filter(b => {
              const anim = b.kind === "muzzle-flash" ? MUZZLE_FLASH_ANIM : EXPLOSION_ANIM
              return now - b.startedAt < anim.frames * anim.frameMs
            })
            for (const b of g.bursts) {
              const anim = b.kind === "muzzle-flash" ? MUZZLE_FLASH_ANIM : EXPLOSION_ANIM
              const frames = this.frameSets[b.kind]
              const frameIndex = Math.min(anim.frames - 1, Math.floor((now - b.startedAt) / anim.frameMs))
              const frame = frames && frames[frameIndex]
              const size = cellSize * (b.kind === "muzzle-flash" ? 0.5 : 0.8)

              if (frame && frame.complete && frame.naturalWidth > 0) {
                ctx.drawImage(frame, b.x - size / 2, b.y - size / 2, size, size)
              }
            }

            if (g.status === "prep") {
              const remainingMs = g.phaseEndsAt - now
              if (remainingMs > 0 && remainingMs <= COUNTDOWN_MS) {
                this.drawCountdown(remainingMs)
              }
            } else if (g.status === "wave" && g.waveStartedAt) {
              const sinceStart = now - g.waveStartedAt
              if (sinceStart < GO_FLASH_MS) {
                this.drawGoFlash(sinceStart)
              }
            }
          },

          drawCountdown(remainingMs) {
            const ctx = this.ctx
            const second = Math.ceil(remainingMs / 1000)
            const fraction = (remainingMs % 1000) / 1000
            const scale = 1 + fraction * 0.4
            const cx = this.canvas.width / 2
            const cy = this.canvas.height / 2

            ctx.save()
            ctx.fillStyle = "rgba(0,0,0,0.45)"
            ctx.fillRect(0, 0, this.canvas.width, this.canvas.height)

            ctx.translate(cx, cy)
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"

            ctx.font = "bold 22px sans-serif"
            ctx.fillStyle = "#fde047"
            ctx.fillText("WAVE STARTS IN", 0, -80)

            ctx.scale(scale, scale)
            ctx.font = "bold 130px sans-serif"
            ctx.lineWidth = 6
            ctx.strokeStyle = "rgba(0,0,0,0.6)"
            ctx.strokeText(String(second), 0, 10)
            ctx.fillStyle = "#ffffff"
            ctx.fillText(String(second), 0, 10)
            ctx.restore()
          },

          drawGoFlash(sinceStart) {
            const ctx = this.ctx
            const alpha = 1 - sinceStart / GO_FLASH_MS

            ctx.save()
            ctx.globalAlpha = alpha
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.font = "bold 110px sans-serif"
            ctx.lineWidth = 6
            ctx.strokeStyle = "rgba(0,0,0,0.6)"
            ctx.strokeText("GO!", this.canvas.width / 2, this.canvas.height / 2)
            ctx.fillStyle = "#22c55e"
            ctx.fillText("GO!", this.canvas.width / 2, this.canvas.height / 2)
            ctx.restore()
          },

          drawHouseIcon(canvasHeight) {
            const ctx = this.ctx
            const cx = 22
            const cy = canvasHeight / 2

            ctx.save()
            ctx.fillStyle = "#4a3222"
            ctx.fillRect(cx - 16, cy - 4, 32, 24)
            ctx.beginPath()
            ctx.moveTo(cx - 20, cy - 4)
            ctx.lineTo(cx, cy - 22)
            ctx.lineTo(cx + 20, cy - 4)
            ctx.closePath()
            ctx.fillStyle = "#7f1d1d"
            ctx.fill()
            ctx.fillStyle = "#2b1a10"
            ctx.fillRect(cx - 4, cy + 6, 8, 14)
            ctx.restore()
          },

          drawHpBar(cx, y, width, hp, maxHp) {
            const ctx = this.ctx
            const h = 4
            const x = cx - width / 2
            ctx.fillStyle = "rgba(0,0,0,0.4)"
            ctx.fillRect(x, y, width, h)
            ctx.fillStyle = hp / maxHp > 0.4 ? "#22c55e" : "#ef4444"
            ctx.fillRect(x, y, width * Math.max(hp / maxHp, 0), h)
          }
        }
      </script>
    </Layouts.app>
    """
  end

  defp defender_tip(:shooter),
    do: "Fires at zombies in range. Fragile - keep a blocker in front of it in the same lane."

  defp defender_tip(:cannon),
    do: "Costs more than a Shooter but hits harder and reaches further. Still fragile up close."

  defp defender_tip(:blocker),
    do:
      "High HP, doesn't attack. Blocks a lane so zombies stop to fight it instead of your shooters."
end
