---
name: deployment-gotchas
description: Use when preparing releases or deployment config — runtime.exs vs compile-time config, PHX_HOST/PHX_SERVER, secrets, health checks.
file_patterns:
  - "**/config/*.exs"
auto_suggest: true
---

# Deployment Gotchas

Not a deployment guide — these are the things that break every first Phoenix deploy. Every rule maps to a real production incident pattern.

Adapted from the upstream `deployment-gotchas` skill for this repo: this app deploys to
**Gigalixir** via `git push` (`.github/workflows/elixir.yml`), which builds the release from
`elixir_buildpack.config` and runs migrations via `gigalixir ps:migrate` in a separate CI job
— there's no `bin/migrate` release command or Dockerfile-ordering step to get right by hand
(a `Dockerfile` exists in the repo but Gigalixir's own buildpack, not it, is what CI drives).
The `runtime.exs`/`config.exs` split, `PHX_HOST`/`PHX_SERVER`, secrets, health-check, and log-level
rules below still apply exactly as written, since they're about what the release does at boot,
not how it's built.

## RULES — Follow these with no exceptions

1. **Use `runtime.exs` for secrets and URLs** — `config.exs`/`prod.exs` are compiled into the release and cannot read env vars at boot
2. **Set `PHX_HOST` and `PHX_SERVER=true`** — without these, URL generation breaks and the server won't start
3. **Never hardcode secrets** — use `System.fetch_env!/1` in `runtime.exs` (the `!` crashes on boot if missing, which is what you want)
4. **Split health checks into liveness and readiness** — liveness returns 200 without touching the DB; only readiness queries the database. This repo's `HighSociety.Healthcheck.Supervisor`/`Worker` backs `GET /health` for platform liveness checks — see CLAUDE.md.
5. **Use `config :logger, level: :info` in production** — `:debug` logs query parameters including user data

---

## 1. runtime.exs vs config.exs

**The incident:** App deploys fine but uses the wrong database URL. `DATABASE_URL` was set correctly in the environment, but the release ignores it.

**Why:** `config.exs` and `prod.exs` are evaluated at **compile time** and baked into the release. `runtime.exs` is evaluated at **boot time** and can read environment variables.

**Bad:**
```elixir
# config/prod.exs — compiled into release, cannot read env vars at boot
config :my_app, MyApp.Repo,
  # Evaluated at BUILD time — captures the build machine's env, not the
  # runtime env. Silently wrong in a release; use runtime.exs instead.
  url: System.get_env("DATABASE_URL")
```

**Good:**
```elixir
# config/runtime.exs — evaluated at boot, reads env vars correctly
if config_env() == :prod do
  database_url = System.fetch_env!("DATABASE_URL")

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end
```

**Rule of thumb:** If the value comes from the environment, it goes in `runtime.exs`. If it's a static setting, it goes in `config.exs`.

---

## 2. PHX_HOST and PHX_SERVER

**The incident:** Deploy succeeds, health check passes, but all URLs in emails and redirects point to `localhost:4000`. Or worse — the server doesn't start at all.

**Why:** Without `PHX_SERVER=true`, the Phoenix endpoint doesn't start its HTTP listener. Without `PHX_HOST`, URL helpers generate `localhost` URLs.

**Bad:**
```elixir
# config/runtime.exs — missing host and server config
config :my_app, MyAppWeb.Endpoint,
  url: [host: "localhost"],  # Wrong in production!
  http: [port: 4000]
  # Server doesn't start without server: true
```

**Good:**
```elixir
# config/runtime.exs
if config_env() == :prod do
  host = System.fetch_env!("PHX_HOST")
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :my_app, MyAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    server: true  # Or set PHX_SERVER=true env var
end
```

---

## 3. Never Hardcode Secrets

**The incident:** Secret key leaks into git history via `config/prod.exs`. Rotating it requires a new release.

**Why:** Secrets in compiled config are baked into the release binary and visible in version control.

**Bad:**
```elixir
# config/prod.exs — secret in source code
config :my_app, MyAppWeb.Endpoint,
  secret_key_base: "actual_secret_key_here_in_git_history"
```

**Good:**
```elixir
# config/runtime.exs — read from environment, crash if missing
if config_env() == :prod do
  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

  config :my_app, MyAppWeb.Endpoint,
    secret_key_base: secret_key_base
end
```

**Why `fetch_env!` (with bang):** If the secret is missing, the app crashes immediately on boot with a clear error. Plain `System.get_env/1` returns `nil` when missing and fails later with a confusing error.

```bash
# Generate a secret
mix phx.gen.secret

# Set in environment (never in source) — on Gigalixir, via `gigalixir config:set`
```

---

## 4. Health Endpoints

**The incident:** Load balancer reports the app is healthy, but users see 500 errors. The app boots fine but can't connect to the database.

**Why:** A simple `200 OK` endpoint proves the HTTP server started but nothing else. A health check that queries the database proves the full stack works.

**Liveness vs readiness:** a load balancer *liveness* probe should return 200
without touching the database — a transient DB blip must not remove the whole
fleet. Point deep checks (DB query) at a *readiness* probe only.

```elixir
# router.ex
get "/health/live", HealthController, :live
get "/health/ready", HealthController, :ready

# lib/my_app_web/controllers/health_controller.ex
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  # Liveness: proves the BEAM is up and the endpoint is responding.
  # No DB query — a slow/unavailable database must not take down the
  # whole fleet just because one instance can't reach it.
  def live(conn, _params) do
    send_resp(conn, 200, "OK")
  end

  # Readiness: proves this instance can actually serve traffic.
  def ready(conn, _params) do
    case Ecto.Adapters.SQL.query(MyApp.Repo, "SELECT 1") do
      {:ok, _} ->
        json(conn, %{status: "ok", database: "connected"})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", database: inspect(reason)})
    end
  end
end
```

**Configure your load balancer** with two probes: liveness (restart the instance if this
fails) and readiness (stop routing traffic to this instance if this fails, but don't restart
it — the rest of the fleet may still be healthy). Collapsing both into one endpoint means a DB
blip either gets masked (shallow check) or takes healthy instances out of rotation right when
the DB needs the load to drop (deep check without the split). This repo's current `/health`
(`HighSociety.Healthcheck`) is a single combined endpoint — splitting it is worth considering
if a DB blip ever needs to not take the whole fleet down, but isn't a bug to fix reflexively.

---

## 5. Production Log Level

**The incident:** App runs fine but storage costs spike. Investigation reveals debug logs are writing gigabytes per day, including full SQL queries with user data (emails, addresses).

**Why:** Ecto logs all queries at `:debug` level, including query parameters. In production, this means PII in your logs.

**Bad:**
```elixir
# config/prod.exs
config :logger, level: :debug  # Logs everything including query params
```

**Good:**
```elixir
# config/prod.exs
config :logger, level: :info

# config/runtime.exs — allow override for debugging
if config_env() == :prod do
  log_level =
    case System.get_env("LOG_LEVEL") do
      "debug" -> :debug
      "warning" -> :warning
      "error" -> :error
      _ -> :info
    end

  config :logger, level: log_level
end
```

**What each level includes:**
- `:debug` — SQL queries with parameters, internal state, PII risk
- `:info` — Request lifecycle, business events (recommended for production)
- `:warning` — Recoverable problems
- `:error` — Failures requiring attention

---

## Not Covered (Intentionally)

This skill does not cover platform-specific deployment: Gigalixir buildpack internals, CI/CD
pipeline configuration, or Dockerfile mechanics — see `.github/workflows/elixir.yml` and
Gigalixir's own docs for those.

---

See `security-essentials` skill for secrets management and dependency auditing.
