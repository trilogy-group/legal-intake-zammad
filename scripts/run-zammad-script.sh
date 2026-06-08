#!/bin/bash
#
# Shared wrapper to run Zammad scripts with environment-specific context.
#
# Config JSON files live in zammad-config/{env}/.
# Credential .env files also live in zammad-config/{env}/.env (gitignored, per-developer).
#
# Usage: ./run-zammad-script.sh <env> <script-name>.ts [args...]
#        env: local, staging, or prod
#
# Can be called from legal-intake via:
#   bash ../legal-intake-zammad/scripts/run-zammad-script.sh staging configure-zammad-triggers.ts
#

set -e

if [ $# -lt 2 ]; then
  echo "Usage: $0 <env> <script-name>.ts [args...]"
  echo "  env: local, staging, or prod"
  exit 1
fi

ENV="$1"
SCRIPT_NAME="$2"
shift 2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_DIR="$REPO_DIR/zammad-config/$ENV"

if [ ! -d "$CONFIG_DIR" ]; then
  echo "Error: Config directory not found: $CONFIG_DIR"
  echo "Valid environments: local, staging, prod"
  exit 1
fi

# Set environment context — picked up by all configure/export .ts scripts
export ZAMMAD_ENV_DIR="$CONFIG_DIR"
export ZAMMAD_CONFIG_DIR="$CONFIG_DIR"

# Load credential .env file for this environment
if [ -f "$CONFIG_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$CONFIG_DIR/.env"
  set +a
else
  echo "Warning: .env not found at $CONFIG_DIR/.env"
  echo "  Copy zammad-config/$ENV/.env.example → zammad-config/$ENV/.env and fill in credentials."
fi

# Run the TypeScript script using pnpm exec tsx (tsx + dotenv are devDependencies here)
pnpm --dir "$REPO_DIR" exec tsx "$SCRIPT_DIR/$SCRIPT_NAME" "$@"
