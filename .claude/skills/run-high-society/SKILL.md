---
name: run-high-society
description: Build, run, and drive the High Society Phoenix app - start the dev server, log in as a test user without touching email, navigate/click/screenshot any page (games, dashboard, poker/battleship tables) with a headless browser. Use when asked to run the app, start the server, log in as a user, take a screenshot of a game/page, or check that a LiveView change actually works in the browser.
---

High Society is a single Phoenix/LiveView app (`mix.exs` at repo root - no
monorepo). It's driven with a small Playwright REPL
(`.claude/skills/run-high-society/driver.mjs`) that logs in via a
locally-minted magic-link token (no email/SMTP involved) and then
accepts `nav`/`click`/`fill`/`screenshot`/`text`/`eval` commands. All
paths below are relative to the repo root.

## Prerequisites

Already verified present in this environment - macOS with Postgres.app
and Homebrew Elixir, so no `apt-get` needed:

```bash
elixir --version   # Elixir 1.20.3 / Erlang-OTP 29
node --version     # v22.12.0
pg_isready          # /tmp:5432 - accepting connections
psql -U postgres -h localhost -lqt | grep high_society
#  high_society_dev  | postgres | ...
#  high_society_test | postgres | ...
```

If `high_society_dev` doesn't exist yet: `mix setup` (deps.get +
ecto.setup + assets.setup + assets.build) from the repo root.

## Setup (one-time, per clone)

```bash
cd .claude/skills/run-high-society
npm install            # installs playwright from package.json
npx playwright install chromium   # downloads the headless browser binary
cd -
```

`node_modules/` here is gitignored (`.claude/skills/*/node_modules/` in
the root `.gitignore`) - `package.json`/`package-lock.json` are
committed, so `npm install` reproduces it.

## Run (agent path)

**1. Start the server:**

```bash
lsof -ti:4000 -sTCP:LISTEN | xargs -r kill   # free the port if a stale server is running
mix phx.server > /tmp/phx_server.log 2>&1 &
disown
# poll for it - macOS has no `timeout(1)` by default, so loop manually:
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/)
  [ "$code" = "200" ] || [ "$code" = "302" ] && break
  sleep 1
done
```

**2. Drive it** by piping commands to `driver.mjs`:

```bash
node .claude/skills/run-high-society/driver.mjs <<'EOF'
login
nav /games/slots
wait #slots-screen
screenshot slots-loaded
click #paytable-button
wait #paytable-modal
screenshot paytable-open
text #paytable-modal
quit
EOF
```

Each line prints one JSON result, e.g. `{"ok":true,"path":"..."}` or
`{"ok":false,"error":"..."}` - check `ok` before trusting the next step.

Screenshots land in `.claude/skills/run-high-society/screenshots/<name>.png`
(gitignored - they're scratch output, not part of the skill).

| command | what it does |
|---|---|
| `login [email]` | Registers (or reuses) that user via `create_test_session.exs`, mints a magic-link token, and clicks through the confirmation page. Defaults to `agent-test@example.com`. |
| `nav <path>` | `page.goto` relative to `http://localhost:4000` (override with `HIGH_SOCIETY_URL`). |
| `click <selector>` | CSS selector, 5s timeout. |
| `clickxy <x> <y>` | Clicks raw viewport coordinates - use for "click outside this element" cases where the target selector's own bounding box covers the point you actually want (e.g. a modal backdrop that's full-screen behind a centered panel). |
| `hover <selector>` | A real pointer hover (not a dispatched event) - needed to trigger CSS `:hover` state, e.g. checking a daisyUI `.tooltip`'s `data-tip` actually shows. |
| `fill <selector> <text>` | Everything after the first space is the value. |
| `wait <selector>` | Waits up to 10s for the selector to appear. |
| `wait-gone <selector>` | Waits up to 10s for the selector to be removed from the DOM - use after a click that should dismiss/remove something (see Gotchas). |
| `text <selector>` | Returns `.innerText` of the first match. |
| `eval <js>` | Runs `page.evaluate(js)`, returns the value. |
| `screenshot [name]` | Defaults to `screenshot.png`. |
| `quit` | Closes the browser and exits. |

**3. Stop the server:** `lsof -ti:4000 -sTCP:LISTEN | xargs -r kill`

### Logging in directly (no browser)

If you just need a valid session URL - e.g. to hand to a different
tool, or to `curl` a LiveView's initial HTML - skip the driver:

```bash
mix run .claude/skills/run-high-society/create_test_session.exs [email]
# EMAIL=agent-test@example.com
# LOGIN_URL=http://localhost:4000/users/log-in/<token>
```

The script is idempotent per email (reuses the user, mints a fresh
token each run) and never touches Swoosh/email - it builds the token
with `UserToken.build_email_token/2` directly and inserts it, the same
call `Accounts.deliver_login_instructions/2` makes internally.

## Run (human path)

`mix phx.server`, then open `http://localhost:4000` in a real browser
and use the normal "email me a magic link" flow. Not useful headlessly
- there's no inbox to read the link from.

## Test

```bash
mix test        # 498 passed, ~3s, at the time this skill was written
```

---

## Gotchas

- **The confirmation-page button text depends on prior login history.**
  A brand-new user's first magic-link visit shows "Confirm and stay
  logged in" / "Confirm and log in only this time"; a user who has
  logged in before (via this flow, or a real one) sees "Keep me logged
  in on this device" / "Log me in only this time" instead - the same
  `UserLive.Confirmation` LiveView renders differently based on
  `user.confirmed_at`. The driver's `login` command matches on the
  substring `"logged in"`, which is common to both first buttons and
  to neither second button - don't narrow that selector to one exact
  phrase or it'll break for half of all users.
- **A magic-link token only gets you to a confirmation page, not a
  logged-in session.** `GET /users/log-in/:token` mounts
  `UserLive.Confirmation`, which still requires the button click (it
  submits the token via a real form POST to `/users/log-in`) - `goto`
  the link and stopping there is not "logged in."
- **Don't race that button click against `waitForNavigation`.** The
  click only fires a LiveView socket event; the real navigation (the
  form POST, then a 302 to `/`) happens asynchronously after the
  server replies, via `phx-trigger-action`.
  `Promise.all([page.waitForNavigation(), page.click(...)])` looks
  like the right pattern but was flaky (~4/5 runs failed) - Phoenix's
  dev-mode LiveReloader injects a same-page iframe that does its own
  frame navigation right around page load, and that seems to satisfy
  `waitForNavigation()` before the real post-click one happens. `login`
  instead does a plain `click()` followed by
  `page.waitForURL(`${BASE_URL}/`)`, which was reliable over 10+ runs.
- **A click that triggers a LiveView-side removal (closing a modal via
  `phx-click`/`phx-click-away`) is not reflected in the DOM the instant
  `click()` returns.** `click()` only waits for the click to dispatch;
  the actual removal happens after a round trip (socket event -> server
  assign -> diff -> patch). Checking with `eval` immediately after such
  a click can read the DOM before the patch lands and wrongly report
  the element as still there. Use `wait-gone <selector>` instead of an
  immediate `eval` check - hit this firsthand confirming the Slots
  paytable modal's click-outside-to-close behavior, where an `eval`
  right after `clickxy` intermittently (and misleadingly) reported the
  modal as still open.
- **macOS has no `timeout(1)`.** The `run` skill's generic polling
  snippets use it; here it's not installed by default. Poll with a
  bounded `for i in $(seq ...)` loop instead (see above).
- **`chromium-cli` (the AppleScript-driven `chrome-cli` wrapper
  installed on this machine) doesn't work in this session** - `open`
  hangs for 15s waiting for a Chrome window that never appears,
  because this session has no attached GUI/display for AppleScript to
  drive. Playwright's own bundled headless Chromium (installed above)
  is what actually works here and is what `driver.mjs` uses - don't
  reach for `chromium-cli` on this project.

## Troubleshooting

- **`create_test_session.exs` raises `UndefinedFunctionError` /
  connection refused**: the app isn't compiled or Postgres isn't up.
  Run `mix compile` and `pg_isready` first.
- **Driver hangs on `login`**: almost always the server isn't actually
  up yet - `mix phx.server` takes a few seconds to bind the port after
  `disown`. Confirm with `curl -s -o /dev/null -w '%{http_code}\n'
  http://localhost:4000/` before running the driver.
- **`page.click: Timeout ... waiting for locator('button:has-text(...)')`
  on the confirmation page**: you're matching the wrong button text for
  this user's confirmation state - see the Gotchas entry above.
