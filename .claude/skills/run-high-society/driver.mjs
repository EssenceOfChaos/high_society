// Stdin REPL for driving the running Phoenix app in a headless browser.
// One command per line; see SKILL.md for the command table.
//
//   node .claude/skills/run-high-society/driver.mjs <<'EOF'
//   login
//   nav /games/slots
//   click #paytable-button
//   screenshot paytable
//   quit
//   EOF
//
// Run from the repo root (paths below - create_test_session.exs, mix -
// are resolved relative to it).

import { chromium } from "playwright";
import { spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import readline from "node:readline";

const BASE_URL = process.env.HIGH_SOCIETY_URL || "http://localhost:4000";
const SHOTS_DIR = ".claude/skills/run-high-society/screenshots";
mkdirSync(SHOTS_DIR, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1000, height: 900 } });
page.on("console", (msg) => {
  if (msg.type() === "error") console.log(`[console error] ${msg.text()}`);
});

function reply(obj) {
  console.log(JSON.stringify(obj));
}

// Mints a magic-link login token for `email` via create_test_session.exs
// (bypasses Swoosh entirely - see that script) and drives the two-step
// confirmation flow (Phoenix 1.8 gen.auth's UserLive.Confirmation page)
// to land on an authenticated session.
async function login(email) {
  const result = spawnSync(
    "mix",
    ["run", ".claude/skills/run-high-society/create_test_session.exs", email || "agent-test@example.com"],
    { encoding: "utf8" }
  );
  if (result.status !== 0) {
    throw new Error(`create_test_session.exs failed: ${result.stderr}`);
  }
  const line = result.stdout.split("\n").find((l) => l.startsWith("LOGIN_URL="));
  if (!line) throw new Error(`no LOGIN_URL in output:\n${result.stdout}`);
  const loginUrl = line.slice("LOGIN_URL=".length).trim();

  await page.goto(loginUrl, { waitUntil: "load" });
  // First visit to a fresh magic-link token lands on a confirmation
  // page, not a direct redirect - a second click is required even
  // though the token itself is already valid. The button's text
  // depends on whether this user has ever confirmed before ("Confirm
  // and stay logged in" the first time, "Keep me logged in on this
  // device" on every login after) - "logged in" is the substring
  // common to both, and to no other button on that page.
  //
  // The click only fires a LiveView "submit" event over the socket;
  // the real navigation (a plain form POST to UserSessionController,
  // then a 302 to "/") happens asynchronously after the server reply,
  // via `phx-trigger-action`. Racing that with
  // `Promise.all([page.waitForNavigation(), page.click(...)])` looked
  // right but was flaky (~4/5 runs) - Phoenix's dev-mode LiveReloader
  // injects a same-page iframe that does its own frame navigation
  // right around page load, and that appears to satisfy
  // `waitForNavigation()` before the real post-click one happens.
  // `waitForURL` against the known post-login destination sidesteps
  // it entirely - confirmed over 6 straight runs with none of the
  // flakiness.
  await page.click('button:has-text("logged in")');
  await page.waitForURL(`${BASE_URL}/`, { timeout: 10000 });
  return page.url();
}

const rl = readline.createInterface({ input: process.stdin });

for await (const raw of rl) {
  const line = raw.trim();
  if (!line) continue;
  const [cmd, ...rest] = line.split(" ");
  const arg = rest.join(" ");

  try {
    switch (cmd) {
      case "login": {
        const url = await login(arg);
        reply({ ok: true, url });
        break;
      }
      case "nav": {
        await page.goto(new URL(arg, BASE_URL).toString(), { waitUntil: "load" });
        reply({ ok: true, url: page.url() });
        break;
      }
      case "initscript": {
        // Runs before every subsequent navigation's page scripts - for
        // state a page hook reads on `mounted()` (e.g. `window.navigator
        // .standalone`, `matchMedia`) that has to be in place *before*
        // load, not patched in after via `eval` once hooks have already
        // run and read the real value.
        await page.addInitScript(arg);
        reply({ ok: true });
        break;
      }
      case "click": {
        await page.click(arg, { timeout: 5000 });
        reply({ ok: true });
        break;
      }
      case "hover": {
        // A real pointer hover, not a dispatched "mouseover" event - CSS
        // :hover (what daisyUI's tooltip component relies on) only
        // activates from the browser's actual pointer state.
        await page.hover(arg, { timeout: 5000 });
        reply({ ok: true });
        break;
      }
      case "clickxy": {
        const [x, y] = arg.split(" ").map(Number);
        await page.mouse.click(x, y);
        reply({ ok: true });
        break;
      }
      case "fill": {
        const sp = arg.indexOf(" ");
        await page.fill(arg.slice(0, sp), arg.slice(sp + 1));
        reply({ ok: true });
        break;
      }
      case "viewport": {
        const [width, height] = arg.split(" ").map(Number);
        await page.setViewportSize({ width, height });
        reply({ ok: true });
        break;
      }
      case "wait": {
        await page.waitForSelector(arg, { timeout: 10000 });
        reply({ ok: true });
        break;
      }
      case "wait-gone": {
        // For confirming something a click removed - e.g. a modal
        // dismissed by a phx-click(-away) handler. That's a server
        // round trip (client -> socket event -> server assign -> diff
        // -> DOM patch), not instantaneous: checking with `eval`
        // immediately after the click reads the DOM before the patch
        // lands and reports the element as still present. `wait-gone`
        // polls instead of assuming either instantaneous removal or a
        // guessed delay.
        await page.waitForSelector(arg, { state: "detached", timeout: 10000 });
        reply({ ok: true });
        break;
      }
      case "text": {
        const text = await page.locator(arg).innerText();
        reply({ ok: true, text });
        break;
      }
      case "eval": {
        const value = await page.evaluate(arg);
        reply({ ok: true, value });
        break;
      }
      case "screenshot": {
        const name = arg || "screenshot";
        const path = `${SHOTS_DIR}/${name}.png`;
        await page.screenshot({ path });
        reply({ ok: true, path });
        break;
      }
      case "quit": {
        await browser.close();
        process.exit(0);
      }
      default:
        reply({ ok: false, error: `unknown command: ${cmd}` });
    }
  } catch (err) {
    reply({ ok: false, error: String(err.message || err) });
  }
}

await browser.close();
