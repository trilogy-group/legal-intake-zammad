#!/bin/bash
# Apply all Zammad configuration from local JSON files
#
# Usage: ./configure-all-zammad-config.sh <env>
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

echo "=== Configuring All Zammad Resources ($ENV_UPPER) ==="
echo ""

echo "1/12 Configuring settings..."
$WRAPPER "$ENV" configure-zammad-settings.ts

echo ""
echo "2/12 Configuring triggers..."
$WRAPPER "$ENV" configure-zammad-triggers.ts

echo ""
echo "3/12 Configuring webhooks..."
$WRAPPER "$ENV" configure-zammad-webhooks.ts

echo ""
echo "4/12 Configuring schedulers..."
$WRAPPER "$ENV" configure-zammad-schedulers.ts

echo ""
echo "5/12 Configuring groups..."
$WRAPPER "$ENV" configure-zammad-groups.ts

echo ""
echo "6/12 Configuring roles..."
$WRAPPER "$ENV" configure-zammad-roles.ts

echo ""
echo "7/12 Configuring organizations..."
$WRAPPER "$ENV" configure-zammad-organizations.ts

echo ""
echo "8/12 Configuring overviews..."
$WRAPPER "$ENV" configure-zammad-overviews.ts

echo ""
echo "9/12 Configuring text modules..."
$WRAPPER "$ENV" configure-zammad-text-modules.ts

echo ""
echo "10/12 Configuring core workflows..."
$WRAPPER "$ENV" configure-zammad-core-workflows.ts

echo ""
echo "11/12 Configuring field visibility..."
$WRAPPER "$ENV" configure-zammad-field-visibility.ts

echo ""
echo "12/12 Configuring report profiles..."
$WRAPPER "$ENV" configure-zammad-report-profiles.ts

echo ""
echo "=== Configuration Complete ==="
echo "All resources have been configured in Zammad"
