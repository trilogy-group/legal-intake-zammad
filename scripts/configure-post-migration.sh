#!/bin/bash
#
# Run all POST-MIGRATION Zammad configuration scripts
#
# This script configures automation and security features in Zammad
# AFTER migrating users, organizations, and tickets.
#
# Usage: ./configure-post-migration.sh <env>
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
echo "🔧 Zammad Post-Migration Configuration ($ENV_UPPER)"
echo "================================================"
echo ""
echo "This will configure automation and security AFTER data migration."
echo ""

# Phase 3: Automation & Security
echo "📋 Phase 3: Automation & Security"
echo "----------------------------------"
echo ""

echo "1/3 Configuring triggers (email notifications)..."
$WRAPPER "$ENV" configure-zammad-triggers.ts
echo "✅ Triggers configured"
echo ""

echo "2/3 Configuring schedulers (time-based automation)..."
$WRAPPER "$ENV" configure-zammad-schedulers.ts
echo "✅ Schedulers configured"
echo ""

echo "3/3 Updating article translations..."
$WRAPPER "$ENV" update-article-translations.ts
echo "✅ Translations updated"
echo ""

echo "================================================"
echo "✅ Post-Migration Configuration Complete!"
echo "================================================"
echo ""
echo "⚠️  Manual Steps Remaining:"
echo "1. Configure outbound email/SMTP settings"
echo "2. Test email notifications"
echo "3. Disable password login (force OAuth only)"
echo "4. Run production tests"
echo ""
echo "To disable password login after OAuth is tested:"
echo "  Update zammad-settings.json:"
echo "  \"user_show_password_login\": false"
echo "  Then run: npm run zammad:$ENV:configure-settings"
echo ""
