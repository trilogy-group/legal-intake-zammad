#!/bin/bash
#
# Apply full prod-equivalent Zammad configuration to the local instance.
# Called by dev/setup.sh Phase 1. Safe to re-run (all scripts are idempotent).
#
# Prerequisites:
#   - dev/.env must have ZAMMAD_URL and ZAMMAD_TOKEN set
#     (setup.sh writes these automatically after creating an admin PAT)
#   - Local Zammad must be running at http://localhost:3001
#
# Usage (called from legal-intake):
#   npm run zammad:local:configure-all
#   or: bash dev/configure-all.sh  (from legal-intake-zammad root)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# WRAPPER lives in scripts/ (sibling of dev/)
WRAPPER="$SCRIPT_DIR/../scripts/run-zammad-script.sh"

echo "=================================================="
echo "Zammad Local Configuration"
echo "=================================================="
echo ""
echo "Applying full prod-equivalent config to local Zammad."
echo "Each step is idempotent — safe to re-run."
echo ""

echo "1/11 Configuring object attributes (custom li_* fields)..."
bash "$WRAPPER" local configure-zammad-object-attributes.ts
echo "    Done"
echo ""

# After creating custom object attributes, Zammad requires a DB migration to
# make the new columns available for use in conditions (overviews, triggers, etc.).
LOCAL_ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$LOCAL_ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$LOCAL_ENV_FILE"
fi
if [ -n "${ZAMMAD_URL:-}" ] && [ -n "${ZAMMAD_TOKEN:-}" ]; then
  echo "    Executing object attribute DB migrations..."
  curl -sf -X POST \
    -H "Authorization: Token token=${ZAMMAD_TOKEN}" \
    -H "Content-Type: application/json" \
    "${ZAMMAD_URL}/api/v1/object_manager_attributes/execute_migrations" > /dev/null \
    && echo "    Migration executed." || echo "    Migration endpoint returned error (may already be current)."
  sleep 3
fi
echo ""

echo "2/11 Configuring system settings (branding, FQDN=localhost, http)..."
bash "$WRAPPER" local configure-zammad-settings.ts
echo "    Done"
echo ""

echo "3/11 Configuring groups..."
bash "$WRAPPER" local configure-zammad-groups.ts
echo "    Done"
echo ""

echo "4/11 Configuring roles (Admin, Agent, Legal Admin, Customer)..."
bash "$WRAPPER" local configure-zammad-roles.ts
echo "    Done"
echo ""

echo "5/11 Configuring ticket states..."
bash "$WRAPPER" local configure-zammad-ticket-states.ts
echo "    Done"
echo ""

echo "6/11 Configuring core workflows..."
bash "$WRAPPER" local configure-zammad-core-workflows.ts
echo "    Done"
echo ""

echo "7/11 Configuring field visibility..."
bash "$WRAPPER" local configure-zammad-field-visibility.ts
echo "    Done"
echo ""

echo "8/11 Configuring overviews..."
bash "$WRAPPER" local configure-zammad-overviews.ts
echo "    Done"
echo ""

echo "9/11 Configuring text modules..."
bash "$WRAPPER" local configure-zammad-text-modules.ts
echo "    Done"
echo ""

echo "10/11 Configuring report profiles..."
bash "$WRAPPER" local configure-zammad-report-profiles.ts
echo "    Done"
echo ""

echo "11/11 Configuring schedulers..."
bash "$WRAPPER" local configure-zammad-schedulers.ts
echo "     Done"
echo ""

echo "=================================================="
echo "All config applied."
echo "=================================================="
echo ""
