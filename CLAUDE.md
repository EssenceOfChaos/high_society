# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

HighSociety is a Phoenix/LiveView casino-style app: users earn a closed-loop rewards currency
called **Tokens** (`users.tokens_balance`, an integer count with no cash value or redemption
path outside the app — see `HighSociety.Tokens`) and spend it across several games — War,
Blackjack, Slots, Roulette, Poker, Battleship, and Zombie Attack. Poker and Battleship are
real-time multiplayer, backed by per-table/per-match GenServers; the rest are solo, backed by
a single Postgres row per user.

Framework-level conventions (Phoenix 1.8 layout/auth patterns, LiveView streams, HEEx syntax,
Ecto changeset rules, form handling) are documented in `AGENTS.md` in this repo — read it
before writing LiveView or Ecto code, its rules are not repeated here.

## Commands

```
mix setup                 # deps.get + ecto.setup + assets.setup + assets.build
mix phx.server             # run the app (localhost:4000); iex -S mix phx.server for a shell
mix test                   # full suite (creates/migrates the test DB first)
mix test test/path/to_test.exs        # single file
mix test test/path/to_test.exs:42     # single test at line 42
mix test --failed          # re-run only what failed last time
mix precommit              # compile --warnings-as-errors, deps.unlock --unused, format, test
mix format                 # format .ex/.exs/.heex per .formatter.exs
mix sobelow --exit low     # security static analysis (also runs in CI on `main`)
```

Run `mix precommit` before considering a change done — it's the CI gate in miniature.

## Architecture

### Solo games: pure logic + Ecto row, translated by a context

Each solo game (War, Blackjack, Slots, Roulette) is three pieces:

- **A pure struct/module** (`HighSociety.Games.War`, `.Blackjack`, `.Slots`, `.Roulette`) —
  no I/O, just game rules operating on a struct with atom keys.
- **An Ecto schema** (`WarGame`, `BlackjackGame`, ...) — one row per user, persisting the
  same shape but with string keys/values (JSON-ish embedded maps), since Ecto/Postgres can't
  round-trip atoms.
- **`HighSociety.Games`** — the context. Every public function loads the Ecto row, converts
  it to the pure struct (`to_war/1`, `to_blackjack/1`, ...), calls the pure game logic, then
  converts back and persists (`stringify_*`/`atomize_*` helper pairs). Token debits/credits
  go through `HighSociety.Accounts.adjust_tokens_balance/4` (itself wrapped in `Repo.transact/1`)
  alongside the game-state write, so a bet, its DB row, and its ledger entry always move
  together.

Only one active row is kept per user per game (previous rows are deleted on a new
round/spin), except Blackjack, which keeps the most recent row regardless of status because a
bet is debited the instant a round is dealt and must be resumable on remount.

### Multiplayer games: one GenServer per table/match

Poker and Battleship each run as a GenServer that is the single authoritative process for one
table/match — every seat/act/fire call is a `GenServer.call`, so concurrent players can never
race the way two LiveViews independently writing Postgres could.

- **Poker** (`HighSociety.Games.PokerTable`): a fixed, compile-time list of tables
  (`PokerTables`), started by a static `PokerTablesSupervisor` under `HighSociety.Games.PokerRegistry`
  (`{:via, Registry, ...}` by slug). Durable state persists to a `PokerTableState` row after
  every change so a crash/deploy never loses seated players' Tokens; `init/1` reloads it and
  resolves any timed-out action immediately.
- **Battleship** (`HighSociety.Games.BattleshipMatch`): matches are created ad hoc at runtime
  under a `DynamicSupervisor` (`BattleshipMatchesSupervisor`) with `restart: :transient` — a
  clean finish (`:normal` stop) is never restarted, but a crash is, reloading from
  `BattleshipMatchState`. `Application.start/2` calls
  `rehydrate_in_flight_matches!/0` off the main boot path to relaunch every non-terminal match
  after a deploy/restart.
- Both broadcast state changes over `Phoenix.PubSub` (topic per table/match slug); LiveViews
  subscribe on mount and re-render from broadcasts rather than polling.
- `HighSociety.Games.PokerBots` seats two bot accounts in dev only (`enabled?/0`) so a
  solo dev session still has a playable table.

### Accounts & Tokens

- `HighSociety.Accounts.adjust_tokens_balance/4` (`user, delta, source, metadata \\ %{}`) is
  the only way `tokens_balance` changes — a guarded `Repo.update_all`
  (`WHERE tokens_balance + delta >= 0`) so concurrent debits can never take a user negative,
  wrapped in `Repo.transact/1` alongside an insert into `token_transactions` (an append-only
  audit ledger keyed by `source`, e.g. `"blackjack_bet"`, `"poker_cash_out"`). The ledger is
  write-only — never read back to compute a balance — so it adds an audit trail without
  weakening the balance update's race-safety or adding a second round trip on the hot path.
  Every one of the six starting-grant functions (`claim_blackjack_tokens/1`,
  `claim_battleship_tokens/1`, ...) writes a matching ledger row the same way.
- All Token amounts are plain integers everywhere (balances, bets, pots, stacks) — the same
  numeric scale carried over unchanged from when the app briefly modeled this as cents-based
  play money; there's no cash value or currency conversion involved. `HighSociety.Tokens.format/1`
  is the one place an amount becomes a comma-grouped display string; callers append the word
  "Tokens" themselves where the surrounding copy doesn't already make the unit clear.
- `Accounts.Scope` wraps `current_scope.user` and is threaded as the first argument through
  context functions that touch a specific user's data (per the auth conventions in `AGENTS.md`).

### CSP: no inline styles, no un-nonced inline scripts

The router sets a strict CSP (`HighSocietyWeb.Router.put_csp_headers/2`) with no
`'unsafe-inline'` for scripts or styles. Consequences that are easy to violate silently
(broken only in prod, not dev/test — see `test/high_society_web/csp_compliance_test.exs`,
which statically greps for both):

- **Never write `style="..."` in a template.** Set the value via a `phx-hook` that mutates
  `el.style` in JS instead (CSP governs the HTML attribute, not CSSOM mutations) — see the
  `.InlineStyle` hook used in `war.ex`/`poker_table.ex` for the pattern.
- **Never write a raw `<script>` tag in HEEx** unless it has `src=`, is a colocated
  `Phoenix.LiveView.ColocatedHook`, or carries the per-request `@csp_nonce`.
- The router pipeline already sets secure headers via this custom CSP plug — don't add
  `put_secure_browser_headers` elsewhere; Sobelow's `Config.Headers` check flags its absence,
  but it's a false positive here.

### Healthcheck subsystem

`HighSociety.Healthcheck.Supervisor` runs a background `Worker` that periodically checks
service health (currently Postgres, via `Healthcheck.Services.Database`); results back
`GET /health`, used by the platform for liveness checks.

## Deployment

CI (`.github/workflows/elixir.yml`) runs `mix test` against a Postgres 16 service container on
every push/PR to `main`/`staging`, then deploys to Gigalixir: pushes to `main` deploy+migrate
production, pushes to `staging` deploy+migrate the staging app. `sobelow.yml` runs a separate
security scan on `main` and uploads SARIF results to GitHub's Security tab.
