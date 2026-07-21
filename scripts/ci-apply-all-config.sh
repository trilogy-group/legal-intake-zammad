#!/bin/bash
#
# ci-apply-all-config.sh <env>   (env: staging | prod)
#
# COMPLETE, ordered, NON-DESTRUCTIVE apply of all Zammad runtime config for CI
# auto-apply on deploy. Unlike configure-all-zammad-config.sh (which covers only
# 12 of the config types), this runs the FULL canonical dependency order derived
# from configure-pre-migration.sh + configure-post-migration.sh, PLUS the types
# those miss (webhooks, organizations, kb), and fires the object-manager
# migration after object-attributes (which its own script does NOT do).
#
# SAFETY:
#   - NEVER sets any DELETE_UNLISTED_* flag  → create/update only, never prune.
#   - Uses the non-`local` configure scripts only (local-triggers deletes
#     unconditionally and is intentionally excluded).
#   - Each step is idempotent (reports "unchanged" when nothing changed), so a
#     re-run / rerun-on-failure is safe.
#
# CREDENTIALS: reads ZAMMAD_URL + ZAMMAD_TOKEN from the ENVIRONMENT (GitHub
# Environment secrets in CI). The per-env zammad-config/<env>/.env is NOT
# required here; run-zammad-script.sh will warn it's missing, which is fine
# because the vars are already exported.
#
set -eu

if [ $# -lt 1 ]; then
  echo "Usage: $0 <env>   (env: staging | prod)"
  exit 1
fi

ENV="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$SCRIPT_DIR/run-zammad-script.sh"
CONFIG_DIR="$REPO_DIR/zammad-config/$ENV"

if [ -z "${ZAMMAD_URL:-}" ] || [ -z "${ZAMMAD_TOKEN:-}" ]; then
  echo "ERROR: ZAMMAD_URL and ZAMMAD_TOKEN must be set in the environment." >&2
  exit 1
fi

echo "=== CI apply Zammad config ($ENV) → $ZAMMAD_URL ==="

# Run a configure script only if its backing JSON exists for this env.
# Args: <config-json-basename> <configure-script.ts>
run_if_present() {
  local json="$CONFIG_DIR/$1"
  local script="$2"
  if [ -f "$json" ]; then
    echo ""
    echo ">>> $script  (from $1)"
    "$WRAPPER" "$ENV" "$script"
  else
    echo "--- skip $script: $1 not present for $ENV"
  fi
}

# Fire the object-manager migration (rebuilds ticket schema/UI so newly defined
# custom fields take effect). configure-zammad-object-attributes.ts does NOT do
# this itself. Idempotent — a no-op when there are no pending migrations.
execute_object_manager_migrations() {
  echo ""
  echo ">>> POST /api/v1/object_manager_attributes_execute_migrations"
  local code
  code=$(curl -s -o /tmp/ci-objmgr-migrate.json -w "%{http_code}" \
    -X POST "$ZAMMAD_URL/api/v1/object_manager_attributes_execute_migrations" \
    -H "Authorization: Bearer $ZAMMAD_TOKEN" \
    -H "Content-Type: application/json" --max-time 120)
  if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
    echo "    migration executed (HTTP $code)"
  else
    echo "ERROR: object-manager migration failed (HTTP $code):" >&2
    head -c 400 /tmp/ci-objmgr-migrate.json >&2 || true
    exit 1
  fi
  # Trap 5 (from the deploy skill): the migration restarts Zammad's workers to
  # rebuild the ticket model, so the WHOLE API can 502 for ~10s afterward. Poll a
  # cheap authenticated endpoint until it recovers BEFORE the next configure step,
  # or that step fails spuriously. Not fatal — just wait it out.
  echo "    waiting for API to recover post-migration..."
  local i rc
  for i in $(seq 1 20); do
    rc=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
      -H "Authorization: Bearer $ZAMMAD_TOKEN" "$ZAMMAD_URL/api/v1/ticket_states" || echo "000")
    if [ "$rc" = "200" ]; then echo "    API healthy (attempt $i)"; return 0; fi
    echo "      attempt $i: HTTP $rc — retrying in 3s"; sleep 3
  done
  echo "ERROR: Zammad API did not recover within ~60s after migration." >&2
  exit 1
}

# --- Canonical dependency order -------------------------------------------------
# 1. Custom-field DEFINITIONS first, then execute the migration so the schema
#    exists before anything references those fields.
run_if_present "zammad-object-attributes.json" "configure-zammad-object-attributes.ts"
execute_object_manager_migrations

# 2. Core infrastructure.
run_if_present "zammad-settings.json"        "configure-zammad-settings.ts"
run_if_present "zammad-groups.json"          "configure-zammad-groups.ts"
run_if_present "zammad-roles.json"           "configure-zammad-roles.ts"
run_if_present "zammad-ticket-states.json"   "configure-zammad-ticket-states.ts"
run_if_present "zammad-organizations.json"   "configure-zammad-organizations.ts"

# 3. Field-dependent config (references the custom fields migrated above).
#    Order matches the proven manual recipe: field-visibility BEFORE core-workflows.
run_if_present "zammad-field-visibility.json" "configure-zammad-field-visibility.ts"
run_if_present "zammad-core-workflows.json"  "configure-zammad-core-workflows.ts"
run_if_present "zammad-overviews.json"       "configure-zammad-overviews.ts"
run_if_present "zammad-text-modules.json"    "configure-zammad-text-modules.ts"
run_if_present "zammad-report-profiles.json" "configure-zammad-report-profiles.ts"
run_if_present "zammad-kb.json"              "configure-zammad-kb.ts"

# 4. Automation last (depends on states/groups/fields existing).
run_if_present "zammad-triggers.json"        "configure-zammad-triggers.ts"
run_if_present "zammad-schedulers.json"      "configure-zammad-schedulers.ts"
run_if_present "zammad-webhooks.json"        "configure-zammad-webhooks.ts"

# 5. Inbound email channel settings (active/group). Channel CREATION is a
#    one-time bootstrap (scripts/bootstrap-inbound-email-channel.rb) — this
#    only syncs mutable settings and skips (with a notice) if the channel
#    doesn't exist yet.
run_if_present "zammad-email-channels.json"  "configure-inbound-email.ts"

# 6. Postmaster filters (e.g. mark redline replies internal). Ordered after the
#    email channel so the mailbox exists; idempotent create/update, never deletes.
run_if_present "zammad-postmaster-filters.json" "configure-postmaster-filters.ts"

echo ""
echo "=== Config apply complete ($ENV) ==="
