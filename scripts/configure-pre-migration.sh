#!/bin/bash
#
# Run all PRE-MIGRATION Zammad configuration scripts
#
# This script configures the foundational infrastructure in Zammad
# BEFORE migrating users, organizations, or tickets.
#
# Usage: ./configure-pre-migration.sh <env>
#        env: staging or prod
#

set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 <env>"
  echo "  env: staging or prod"
  exit 1
fi

ENV="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/run-zammad-script.sh"

ENV_UPPER=$(echo "$ENV" | tr '[:lower:]' '[:upper:]')

echo "================================================"
echo "🚀 Zammad Pre-Migration Configuration ($ENV_UPPER)"
echo "================================================"
echo ""
echo "This will configure Zammad infrastructure BEFORE data migration."
echo "Scripts will run in dependency order."
echo ""

# Phase 1: Infrastructure Setup
echo "📋 Phase 1: Infrastructure Setup"
echo "--------------------------------"
echo ""

echo "1/10 Configuring object attributes (custom fields definition)..."
$WRAPPER "$ENV" configure-zammad-object-attributes.ts
echo "✅ Object attributes configured"
echo "⚠️  Remember to execute database migrations in Admin UI!"
echo ""

echo "2/10 Configuring system settings (branding, auth, timezone)..."
$WRAPPER "$ENV" configure-zammad-settings.ts
echo "✅ System settings configured"
echo ""

echo "3/10 Configuring groups (Existing Vendor, Property Leases, etc.)..."
$WRAPPER "$ENV" configure-zammad-groups.ts
echo "✅ Groups configured"
echo ""

echo "4/10 Configuring roles (Admin, Agent, Legal Admin, Customer)..."
$WRAPPER "$ENV" configure-zammad-roles.ts
echo "✅ Roles configured"
echo ""

echo "5/10 Configuring ticket states (open, closed, under review, etc.)..."
$WRAPPER "$ENV" configure-zammad-ticket-states.ts
echo "✅ Ticket states configured"
echo ""

echo "6/10 Configuring core workflows (field visibility, conditionals)..."
$WRAPPER "$ENV" configure-zammad-core-workflows.ts
echo "✅ Core workflows configured"
echo ""

echo "7/10 Configuring field visibility..."
$WRAPPER "$ENV" configure-zammad-field-visibility.ts
echo "✅ Field visibility configured"
echo ""

echo "8/10 Configuring overviews (ticket list views)..."
$WRAPPER "$ENV" configure-zammad-overviews.ts
echo "✅ Overviews configured"
echo ""

echo "9/10 Configuring text modules (response templates)..."
$WRAPPER "$ENV" configure-zammad-text-modules.ts
echo "✅ Text modules configured"
echo ""

echo "10/10 Configuring report profiles..."
$WRAPPER "$ENV" configure-zammad-report-profiles.ts
echo "✅ Report profiles configured"
echo ""

echo "================================================"
echo "✅ Pre-Migration Configuration Complete!"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Migrate organizations via Legal Intake app"
echo "2. Migrate users via Legal Intake app"
echo "3. Migrate tickets via Legal Intake app"
echo "4. Run post-migration setup: npm run zammad:$ENV:configure-post-migration"
echo ""
