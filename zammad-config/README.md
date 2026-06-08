# Zammad Configuration

JSON configuration files for all environments. Applied via TypeScript scripts in `legal-intake-zammad/scripts/`, invoked through `pnpm` scripts defined in `legal-intake-zammad/package.json`.

## Structure

```
zammad-config/
├── local/     ← local dev config (localhost overrides, http, password login enabled)
├── staging/   ← staging config (staging FQDN, staging webhook URL)
└── prod/      ← production config (source of truth)
```

Each environment directory also contains a gitignored `.env` with API credentials (copy from `.env.example`).

## Applying config

```bash
# From legal-intake-zammad/

# Apply a single config type to local
pnpm run zammad:local:configure-settings
pnpm run zammad:local:configure-triggers
pnpm run zammad:local:configure-roles
pnpm run zammad:local:configure-groups
pnpm run zammad:local:configure-overviews
pnpm run zammad:local:configure-object-attributes
pnpm run zammad:local:configure-core-workflows
pnpm run zammad:local:configure-ticket-states
pnpm run zammad:local:configure-text-modules
pnpm run zammad:local:configure-schedulers

# Apply all config to local
pnpm run zammad:local:configure-all

# Apply all config to staging
pnpm run zammad:staging:configure-all

# Apply all config to prod
pnpm run zammad:prod:configure-all
```

Scripts are **idempotent** — re-running reports `unchanged` for anything already in the desired state, and only pushes real diffs.

## Making a config change

1. Edit the JSON file in the appropriate `zammad-config/{env}/` directory
2. Apply it:

```bash
# Example: tweak a setting on local
vim zammad-config/local/zammad-settings.json
pnpm run zammad:local:configure-settings

# Example: add a trigger to staging
vim zammad-config/staging/zammad-triggers.json
pnpm run zammad:staging:configure-triggers
```

## Exporting from a live instance

Captures the current state of a live Zammad into local JSON files:

```bash
pnpm run zammad:staging:export-all
pnpm run zammad:prod:export-all
```

## Environment differences

| File | local | staging | prod |
|------|-------|---------|------|
| `zammad-settings.json` | `fqdn: localhost`, `http_type: http`, password login on | staging FQDN, https | prod FQDN, https |
| `zammad-triggers.json` | webhook → `host.docker.internal:3000` | staging webhook URL | prod webhook URL |
| `zammad-webhooks.json` | created by `setup.sh`, not checked in | staging webhook | prod webhook |
