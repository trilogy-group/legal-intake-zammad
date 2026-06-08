#!/bin/bash
# Export all Zammad configuration from UI to local JSON files
#
# Usage: ./export-all-zammad-config.sh <env>
#        env: staging or prod

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

echo "=== Exporting Zammad Configuration ($ENV_UPPER) ==="
echo ""

echo "1/12 Exporting settings..."
$WRAPPER "$ENV" export-zammad-settings.ts

echo ""
echo "2/12 Exporting triggers..."
$WRAPPER "$ENV" export-zammad-triggers.ts

echo ""
echo "3/12 Exporting webhooks..."
$WRAPPER "$ENV" export-zammad-webhooks.ts

echo ""
echo "4/12 Exporting schedulers..."
$WRAPPER "$ENV" export-zammad-schedulers.ts

echo ""
echo "5/12 Exporting roles..."
$WRAPPER "$ENV" export-zammad-roles.ts

echo ""
echo "6/12 Exporting overviews..."
$WRAPPER "$ENV" export-zammad-overviews.ts

echo ""
echo "7/12 Exporting text modules..."
$WRAPPER "$ENV" export-zammad-text-modules.ts

echo ""
echo "8/12 Exporting core workflows..."
$WRAPPER "$ENV" export-zammad-core-workflows.ts

echo ""
echo "9/12 Exporting field visibility..."
$WRAPPER "$ENV" export-zammad-field-visibility.ts

echo ""
echo "10/12 Exporting ticket states..."
$WRAPPER "$ENV" export-zammad-ticket-states.ts

echo ""
echo "11/12 Exporting object attributes..."
$WRAPPER "$ENV" export-zammad-object-attributes.ts

echo ""
echo "12/12 Exporting report profiles..."
$WRAPPER "$ENV" export-zammad-report-profiles.ts

echo ""
echo "=== Export Complete ==="
echo "All configuration files have been synced with Zammad UI"
