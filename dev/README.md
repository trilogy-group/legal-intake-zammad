# Local Development Setup

This document covers everything needed to run the full Legal Intake + Zammad stack locally.

The development mode runs the **Zammad app natively** (Rails + Vite on your machine) with infrastructure services (Postgres, Elasticsearch, Redis, Memcached) in Docker. This gives you:

- **Instant frontend changes** — Vite HMR reloads Vue/JS in the browser on save
- **Instant backend changes** — Rails dev mode reloads Ruby files on each request
- **Config changes via API** — no restart needed at all

---

## Prerequisites

| Dependency | Install | Notes |
|---|---|---|
| Docker Desktop | [docker.com](https://www.docker.com/products/docker-desktop/) | Must be running |
| rbenv | `brew install rbenv` | Ruby version manager |
| Ruby 3.4.9 | `rbenv install 3.4.9` | App runtime |
| forego | `brew install forego` | Runs Procfile.dev |
| Node.js 22+ | `brew install node` | For Vite + pnpm |
| pnpm 8+ | `npm install -g pnpm` | Package manager |

**One-time Ruby + Node setup** (inside `legal-intake-zammad/`):
```bash
bundle install   # install Ruby gems
pnpm install     # install Node modules
```

---

## First-time setup

### 1. Start local Supabase (legal-intake)

```bash
cd legal-intake
npx supabase start
npx supabase db push --local
cp .env.example .env
# Fill in NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from supabase start output
```

### 2. Start infra containers

```bash
cd legal-intake-zammad
pnpm run zammad:local:up
```

Starts Postgres, Elasticsearch, Redis, and Memcached in Docker. Waits a few seconds for them to become healthy.

### 3. Copy env file

```bash
cp .env.example .env
# Already has the right defaults — no changes needed
```

### 4. Bootstrap Zammad

```bash
pnpm run zammad:local:setup
```

This script:
- Creates the admin and bot users in Zammad
- Generates API tokens and writes them to `legal-intake/.env`
- Configures the webhook pointing to `https://host.docker.internal:3000`
- Applies all config from `zammad-config/local/`
- Syncs all Supabase users to Zammad as customers/agents

### 5. Start Zammad

```bash
pnpm run zammad:local:dev
```

Starts Rails (port 3001), Vite dev server, WebSocket server, and background worker via Procfile.dev.

### 6. Start legal-intake

```bash
cd legal-intake
pnpm run zammad:local:dev
# → https://localhost:3000 (HTTPS required for webhook delivery)
```

---

## Daily workflow

```bash
# Terminal 1 — start infra
cd legal-intake-zammad && pnpm run zammad:local:up

# Terminal 2 — start Zammad
cd legal-intake-zammad && pnpm run zammad:local:dev

# Terminal 3 — start legal-intake
cd legal-intake && pnpm run zammad:local:dev
```

---

## Testing changes locally

### Frontend changes (Vue, JS, CSS)
Edit any file in `app/frontend/` → Vite hot-reloads the browser instantly. No restart needed.

### Backend changes (Ruby, ERB)
Edit any file in `app/`, `lib/` → Rails dev mode reloads on the next browser request. No restart needed.

### Config changes (roles, triggers, settings, etc.)
Edit `zammad-config/local/<file>.json`, then:
```bash
pnpm run zammad:local:configure-settings     # apply a specific type
pnpm run zammad:local:configure-all          # apply everything
```
No restart needed — applied via API instantly.

---

## Useful commands

```bash
# Infra logs (postgres, elasticsearch, redis, memcached)
pnpm run zammad:local:logs

# Rails console
PATH="$(rbenv prefix)/bin:$PATH" bundle exec rails console

# Stop infra containers
pnpm run zammad:local:down

# Full reset (wipes DB + all data, re-run setup after)
pnpm run zammad:local:down -- -v
pnpm run zammad:local:up
pnpm run zammad:local:setup

# Export current staging/prod config to local JSON files
pnpm run zammad:staging:export-all
pnpm run zammad:prod:export-all
```

---

## Full Docker mode (CI only)

If you need to run the entire stack in Docker without native Rails (e.g. CI, quick smoke test):

```bash
pnpm run zammad:local:docker:up    # full stack in Docker (no HMR, no code reload)
pnpm run zammad:local:docker:down
```

Note: code changes require a Docker image rebuild in this mode.

---

## How the webhook works

**Zammad → legal-intake:**
Zammad POSTs to `https://host.docker.internal:3000/api/zammad/webhook`.
`host.docker.internal` resolves to your Mac from inside Docker containers.

**legal-intake → Zammad:**
`ZAMMAD_URL=http://localhost:3001` in `legal-intake/.env`. Rails listens directly on 3001.

---

## .env files reference

| File | Purpose |
|---|---|
| `legal-intake-zammad/.env` | Native Rails env (DB URL, Redis, ES — gitignored) |
| `legal-intake-zammad/dev/.env` | Local Zammad admin + bot credentials (gitignored) |
| `legal-intake-zammad/zammad-config/local/.env` | API token for local configure-* scripts (gitignored) |
| `legal-intake-zammad/zammad-config/staging/.env` | Staging API token (gitignored) |
| `legal-intake-zammad/zammad-config/prod/.env` | Production API token (gitignored) |
| `legal-intake/.env` | Next.js env — `ZAMMAD_*` keys auto-updated by setup |

All gitignored files have a `.env.example` to copy from.
