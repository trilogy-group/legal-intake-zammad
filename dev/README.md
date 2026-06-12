# Local Development Setup

This document covers everything needed to run the full Legal Intake + Zammad stack locally — it gets
**legal-intake-zammad** running and wired to the **legal-intake** app.

> **Assumed layout:** this guide assumes the two repos are cloned as **siblings** under the same parent
> directory:
>
> ```
> <parent>/
> ├── legal-intake/
> └── legal-intake-zammad/
> ```
>
> `dev/setup.sh` locates legal-intake at `../../legal-intake` relative to itself. If your layout
> differs, set `LEGAL_INTAKE_DIR` when running setup:
> `LEGAL_INTAKE_DIR=/path/to/legal-intake pnpm run zammad:local:setup`.

The full local stack has three parts:

1. **Local Supabase + legal-intake** — the business-side intake app. Set this up by following
   [`legal-intake/README.md`](../../legal-intake/README.md). That repo owns its own Supabase/app
   setup; this guide does **not** duplicate it. The only extra wiring needed when running Zammad
   locally is described in [Wire legal-intake to Zammad](#1-wire-legal-intake-to-zammad) below.
2. **Zammad infrastructure** — Postgres, Elasticsearch, Redis, Memcached, in Docker.
3. **Zammad app** — Rails + Vite, run **natively** on your machine via `bin/dev`.

Running Zammad natively (rather than fully in Docker) gives you:

- **Instant frontend changes** — Vite HMR reloads Vue/JS in the browser on save
- **Instant backend changes** — Rails dev mode reloads Ruby files on each request
- **Config changes via API** — no restart needed at all

> **Ports:** Zammad runs on **http://localhost:3001**, legal-intake runs on **https://localhost:3000**.
> These are not interchangeable — the Zammad → legal-intake webhook targets `https://localhost:3000`,
> and legal-intake calls Zammad at `http://localhost:3001`.

---

## Prerequisites

| Dependency | Install | Notes |
|---|---|---|
| Docker Desktop | [docker.com](https://www.docker.com/products/docker-desktop/) | Must be running |
| rbenv | `brew install rbenv` | Ruby version manager |
| Ruby 3.4.9 | `rbenv install 3.4.9` | App runtime (see `.ruby-version`) |
| forego | `brew install forego` | Runs `Procfile.dev` |
| Node.js 22+ | `brew install node` | For Vite + pnpm |
| pnpm 10+ | `npm install -g pnpm` | Package manager |
| libpq | `brew install libpq` | Native build dep for the `pg` gem |
| imlib2 | `brew install imlib2` | Native build dep for the `rszr` (image) gem |

Make sure rbenv is initialised in your shell (add to `~/.zshrc`), so `ruby`/`bundle`/`gem` resolve to 3.4.9:

```bash
echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc && exec zsh
ruby -v   # => ruby 3.4.9
```

> **Heads up — Bun:** if you have `bun` on your PATH, ExecJS will try to use it for asset
> compilation and Rails will abort. `.env.example` sets `EXECJS_RUNTIME=Node` to prevent this —
> keep it.

**One-time Ruby + Node install** (inside `legal-intake-zammad/`):

```bash
# If the pg gem can't find libpq, point bundler at it once:
bundle config build.pg --with-pg-config=/opt/homebrew/opt/libpq/bin/pg_config

bundle install   # install Ruby gems  (needs libpq + imlib2 from the table above)
pnpm install     # install Node modules
```

---

## First-time setup

### 1. Wire legal-intake to Zammad

Local Supabase and legal-intake itself should already be set up per
[`legal-intake/README.md`](../../legal-intake/README.md) (i.e. `supabase start`, `.env` created,
`npm install`). The only Zammad-specific addition is a webhook signing secret in **`legal-intake/.env`**:

```bash
# in legal-intake/.env — any random string; both sides must agree
ZAMMAD_WEBHOOK_SECRET="$(openssl rand -hex 32)"
```

`setup.sh` (step 5) reads this and also **writes back** `ZAMMAD_URL`, `ZAMMAD_API_TOKEN`,
`ZAMMAD_LEGAL_USER_TOKEN`, `ZAMMAD_LEGAL_USER_ID`, and `IS_LOCAL_ENVIRONMENT=true` automatically.

### 2. Create the Zammad env files

```bash
cd legal-intake-zammad

# Native Rails env (DB/Redis/ES/Memcached + EXECJS_RUNTIME + pool tuning).
# Defaults are correct — no edits needed.
cp .env.example .env

# Local admin + bot credentials used by setup.sh to create the users.
# Fill in the four credential values (login/password for admin and bot).
cp dev/.env.example dev/.env
```

### 3. Start infra containers

```bash
pnpm run zammad:local:up
```

Starts Postgres (host port **5433**), Elasticsearch (**9200**), Redis (**6379**), and Memcached (**11211**).
Wait a few seconds for them to become healthy.

### 4. Initialise the Zammad database (first-time only, native mode)

The infra containers only provide an empty Postgres. Create, migrate, and seed the schema natively:

```bash
set -a; source .env; set +a          # load DATABASE_URL etc.
bundle exec rake zammad:db:init       # db:create + db:migrate + db:seed
bundle exec rails runner "Setting.set('system_init_done', true)"   # skip the first-run wizard
```

### 5. Start Zammad

```bash
pnpm run zammad:local:dev
```

Starts Rails (port **3001**), Vite, the WebSocket server, and the background worker via `Procfile.dev`.
Wait for `Listening on http://127.0.0.1:3001`, then confirm:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3001/api/v1/getting_started   # => 200
```

### 6. Bootstrap Zammad config

In a separate terminal:

```bash
pnpm run zammad:local:setup
```

This script (idempotent — safe to re-run):

- Creates the admin and bot users (from `dev/.env`) and generates API tokens
- Writes the tokens into `legal-intake/.env`
- Configures the webhook → `https://localhost:3000/api/webhooks/zammad`
- Applies all config from `zammad-config/local/` (roles, groups, custom `li_*` fields, triggers, …)
- Syncs all Supabase users into Zammad as customers/agents

### 7. Run the custom-field DB migration (first-time only)

`setup.sh` creates custom object attributes (`li_*`), but Zammad needs a one-time DB migration before
those fields can be used in trigger/overview conditions. On the **first** run, setup will fail on a
trigger with `Invalid object selector conditions` — that's expected. Run the migration, then re-run setup:

```bash
# Option A — via the UI: Admin → Objects → Execute Migrations
#   http://localhost:3001/#system/object-manager
# Option B — via Rails:
bundle exec rails runner "ObjectManager::Attribute.migration_execute"

pnpm run zammad:local:setup   # re-run — now all triggers apply
```

### 8. Save the admin token for standalone config commands

`setup.sh` exports the token into its own environment, so it works without this file. But the
standalone `pnpm run zammad:local:configure-*` commands read it from `zammad-config/local/.env`:

```bash
cp zammad-config/local/.env.example zammad-config/local/.env
# Set ZAMMAD_TOKEN to the value setup.sh wrote into dev/.env (ZAMMAD_TOKEN=...)
```

### 9. Start legal-intake on port 3000

Zammad's webhook targets `https://localhost:3000`, and legal-intake's `dev` script now binds 3000 (HTTPS):

```bash
cd legal-intake
npm run dev
# → https://localhost:3000  (accept the self-signed cert warning)
```

---

## Daily workflow

```bash
# Terminal 1 — infra
cd legal-intake-zammad && pnpm run zammad:local:up

# Terminal 2 — Zammad (native Rails + Vite + worker)
cd legal-intake-zammad && pnpm run zammad:local:dev

# Terminal 3 — legal-intake on 3000
cd legal-intake && npm run dev
```

Re-run `pnpm run zammad:local:setup` any time you want to re-apply config (it's idempotent).

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
No restart needed — applied via API instantly. (Requires `zammad-config/local/.env`, see step 8.)

---

## Useful commands

```bash
# Infra logs
pnpm run zammad:local:logs

# Rails console (native)
set -a; source .env; set +a; bundle exec rails console

# Stop infra containers
pnpm run zammad:local:down

# Full reset (wipes DB + all data, then re-run init + setup)
pnpm run zammad:local:down -- -v
pnpm run zammad:local:up
# then repeat First-time setup steps 4, 5, 6, 7
```

---

## Troubleshooting

| Symptom | Cause & fix |
|---|---|
| `bundle install` fails on `pg` | `libpq` missing. `brew install libpq` then `bundle config build.pg --with-pg-config=/opt/homebrew/opt/libpq/bin/pg_config`. |
| `bundle install` fails on `rszr` | `imlib2` missing. `brew install imlib2`, then re-run `bundle install`. |
| `pnpm install` → `EACCES ... mkdir '/Users/<someone>'` | A stale absolute `store-dir` in `.npmrc`. Remove it so pnpm uses its default store. |
| Rails aborts: *CoffeeScript assets cannot be compiled with 'Bun.sh'* | Bun is on your PATH. Ensure `EXECJS_RUNTIME=Node` is in `.env`. |
| Worker: `ActiveRecord::ConnectionTimeoutError ... pool` | DB pool too small. Ensure `DATABASE_URL` ends with `?pool=50`. |
| Rails can't reach Redis | The infra Redis must be published to the host (`127.0.0.1:6379` in `dev/docker-compose.yml`). |
| `localhost:3001` returns empty / Zammad unreachable | Another process is on 3001 (e.g. a stale legal-intake started before its `dev` script was moved to 3000). Free port 3001 for Zammad; legal-intake belongs on **3000**. |
| setup: `HTTP 422 — Invalid object selector conditions` | Custom `li_*` fields not migrated yet. Run step 7 (object migration), then re-run setup. |
| setup: `HTTP 422 — At least one user needs to have admin permissions` | The seeded permission IDs didn't line up with the config (migrate/seed ordering). Do a full reset (`zammad:local:down -- -v` → `up` → `rake zammad:db:init`) and retry setup. |

---

## Full Docker mode (CI / quick smoke test)

To run the entire stack in Docker without native Rails (no HMR, no code reload):

```bash
pnpm run zammad:local:docker:up
pnpm run zammad:local:docker:down
```

Code changes require a Docker image rebuild in this mode.

---

## How the webhook works

**Zammad → legal-intake:**
Zammad POSTs to `https://localhost:3000/api/webhooks/zammad`. Since Zammad runs natively on the host,
it reaches legal-intake directly via localhost. The payload is signed with HMAC-SHA1 using
`ZAMMAD_WEBHOOK_SECRET` from `legal-intake/.env`.

**legal-intake → Zammad:**
`ZAMMAD_URL=http://localhost:3001` in `legal-intake/.env`. Zammad Rails listens natively on port 3001.

---

## .env files reference

| File | Purpose |
|---|---|
| `legal-intake-zammad/.env` | Native Rails env — DB URL, Redis, ES, Memcached, `EXECJS_RUNTIME`, pool (gitignored; copy from `.env.example`) |
| `legal-intake-zammad/dev/.env` | Local Zammad admin + bot credentials + the API token setup.sh writes (gitignored) |
| `legal-intake-zammad/zammad-config/local/.env` | API token for the standalone `configure-*` scripts (gitignored) |
| `legal-intake-zammad/zammad-config/staging/.env` | Staging API token (gitignored) |
| `legal-intake-zammad/zammad-config/prod/.env` | Production API token (gitignored) |
| `legal-intake/.env` | Next.js env — `ZAMMAD_*` keys auto-written by setup.sh; you add `ZAMMAD_WEBHOOK_SECRET` |

All gitignored files have a `.env.example` to copy from.
