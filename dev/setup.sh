#!/bin/bash
#
# Bootstrap local Zammad: apply full prod-equivalent config, create the
# legal-agent-bot user, configure the webhook, and apply local triggers.
#
# Idempotent — safe to re-run at any time.
#
# Two modes:
#   Docker mode (default): Zammad runs in Docker containers (npm run zammad:local:up)
#   Native mode:           Zammad runs natively via bin/dev in legal-intake-zammad
#                          Set ZAMMAD_NATIVE_MODE=true to use this mode.
#
# Prerequisites (Docker mode):
#   1. Docker Desktop running
#   2. Zammad containers running: npm run zammad:local:up   (from legal-intake)
#   3. legal-intake/.env contains ZAMMAD_WEBHOOK_SECRET
#
# Prerequisites (Native mode):
#   1. pnpm run zammad:local:up  (starts infrastructure containers)
#   2. bin/dev running        (Zammad Rails + worker + websocket)
#   3. legal-intake/.env contains ZAMMAD_WEBHOOK_SECRET
#
# Usage (from legal-intake):
#   npm run zammad:local:setup           # Docker mode
#   npm run zammad:local:native:setup    # Native mode
#
# Direct usage:
#   bash dev/setup.sh                               # Docker mode
#   ZAMMAD_NATIVE_MODE=true bash dev/setup.sh       # Native mode
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ZAMMAD_REPO = legal-intake-zammad root (one level up from dev/)
ZAMMAD_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# ROOT_DIR = legal-intake root (sibling of legal-intake-zammad)
ROOT_DIR="${LEGAL_INTAKE_DIR:-$(cd "$SCRIPT_DIR/../../legal-intake" 2>/dev/null && pwd)}"
LOCAL_DIR="$SCRIPT_DIR"
LOCAL_ENV="$LOCAL_DIR/.env"

# ── Mode detection ────────────────────────────────────────────────────────────
NATIVE_MODE="${ZAMMAD_NATIVE_MODE:-false}"

# Source local .env early so credential variables are available below.
if [ -f "$LOCAL_ENV" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$LOCAL_ENV"
  set +a
fi

# All credentials come from dev/.env (see .env.example for documentation).
ZAMMAD_BASE_URL="http://localhost:3001"
ADMIN_LOGIN="${ZAMMAD_LOCAL_ADMIN_LOGIN:-admin@local}"
ADMIN_PASSWORD="${ZAMMAD_LOCAL_ADMIN_PASSWORD}"
BOT_LOGIN="${ZAMMAD_LOCAL_BOT_LOGIN:-legal-agent-bot@localhost}"
BOT_PASSWORD="${ZAMMAD_LOCAL_BOT_PASSWORD}"

BOT_NAME_FIRST="Legal Agent"
BOT_NAME_LAST="Bot"
WEBHOOK_NAME="Legal Agent (local)"

# Webhook endpoint auto-selection based on mode
if [ -n "${ZAMMAD_WEBHOOK_ENDPOINT:-}" ]; then
  WEBHOOK_ENDPOINT="$ZAMMAD_WEBHOOK_ENDPOINT"
elif [ "$NATIVE_MODE" = "true" ]; then
  WEBHOOK_ENDPOINT="https://localhost:3000/api/webhooks/zammad"
else
  WEBHOOK_ENDPOINT="https://host.docker.internal:3000/api/webhooks/zammad"
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

red()    { printf "\033[31m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
bold()   { printf "\033[1m%s\033[0m\n" "$*"; }

die() { red "Error: $*"; exit 1; }

# Run a Rails runner command against the local Zammad instance.
rails_runner() {
  local ruby_code="$1"
  if [ "$NATIVE_MODE" = "true" ]; then
    (cd "$ZAMMAD_REPO" && RAILS_ENV=development bundle exec rails runner "$ruby_code" 2>/dev/null)
  else
    docker exec dev-zammad-railsserver-1 bundle exec rails runner "$ruby_code" 2>/dev/null
  fi
}

json_field() {
  local json="$1" field="$2"
  echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$field',''))" 2>/dev/null
}

json_array_field() {
  local json="$1" field="$2"
  echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('$field',[])))" 2>/dev/null
}

api() {
  local method="$1" path="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -sf -X "$method" \
      -H "Authorization: Token token=$ADMIN_TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json" \
      "$ZAMMAD_BASE_URL$path" \
      -d "$data"
  else
    curl -sf -X "$method" \
      -H "Authorization: Token token=$ADMIN_TOKEN" \
      -H "Accept: application/json" \
      "$ZAMMAD_BASE_URL$path"
  fi
}

# ── Validate prerequisites ────────────────────────────────────────────────────

[ -n "$ADMIN_PASSWORD" ] || die "ZAMMAD_LOCAL_ADMIN_PASSWORD is not set. Copy dev/.env.example → dev/.env and fill in credentials."
[ -n "$BOT_PASSWORD"   ] || die "ZAMMAD_LOCAL_BOT_PASSWORD is not set. Copy dev/.env.example → dev/.env and fill in credentials."

# Load legal-intake root .env for ZAMMAD_WEBHOOK_SECRET
if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

if [ -z "${ZAMMAD_WEBHOOK_SECRET:-}" ]; then
  die "ZAMMAD_WEBHOOK_SECRET is not set in legal-intake/.env. Add it and re-run."
fi

# ── Ensure local .env exists ──────────────────────────────────────────────────

if [ ! -f "$LOCAL_ENV" ]; then
  cp "$LOCAL_DIR/.env.example" "$LOCAL_ENV"
  echo "Created dev/.env from .env.example"
fi

# ── Helpers for .env persistence ─────────────────────────────────────────────

update_env_var() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$LOCAL_ENV" 2>/dev/null; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$LOCAL_ENV"
  else
    echo "${key}=${value}" >> "$LOCAL_ENV"
  fi
}

# ── Wait for Zammad to be reachable ──────────────────────────────────────────

echo ""
bold "Waiting for Zammad to be reachable at $ZAMMAD_BASE_URL..."
MAX_WAIT=300
ELAPSED=0
INTERVAL=10
until curl -sf -o /dev/null "$ZAMMAD_BASE_URL" 2>/dev/null; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    if [ "$NATIVE_MODE" = "true" ]; then
      die "Zammad did not respond after ${MAX_WAIT}s. Is 'bin/dev' running?"
    else
      die "Zammad did not respond after ${MAX_WAIT}s. Is 'npm run zammad:local:up' running?"
    fi
  fi
  printf "  Still waiting... (%ss elapsed)\r" "$ELAPSED"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done
green "Zammad is reachable."
echo ""

bold "Waiting for Zammad Rails app to finish initializing..."
ELAPSED=0
until rails_runner "puts 'ok'" | grep -q "ok"; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    if [ "$NATIVE_MODE" = "true" ]; then
      die "Rails app did not initialize after ${MAX_WAIT}s. Is 'bin/dev' running?"
    else
      die "Rails app did not initialize after ${MAX_WAIT}s. Check: npm run zammad:local:logs"
    fi
  fi
  printf "  Rails still initializing... (%ss elapsed)\r" "$ELAPSED"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done
green "Rails app is ready."
echo ""

# ── Admin user bootstrap (first-run only) ────────────────────────────────────

ADMIN_EXISTS=$(rails_runner "puts User.exists?(login: '$ADMIN_LOGIN')" | tail -1)

if [ "$ADMIN_EXISTS" != "true" ]; then
  echo "Admin user not found — creating $ADMIN_LOGIN (first-run init)..."
  rails_runner "
UserInfo.current_user_id = 1
u = User.create!(
  login: '$ADMIN_LOGIN', email: '$ADMIN_LOGIN',
  firstname: 'Admin', lastname: 'Local',
  password: '$ADMIN_PASSWORD', active: true,
  roles: Role.where(name: ['Admin', 'Agent'])
)
puts \"Created admin user id=\#{u.id}\"
" | tail -2
  green "Admin user created."
else
  green "Admin user already exists — skipping creation."
fi
echo ""

# ── Admin token: reuse if valid, otherwise create ────────────────────────────

EXISTING_TOKEN=$(grep "^ZAMMAD_TOKEN=" "$LOCAL_ENV" 2>/dev/null | cut -d= -f2)
ADMIN_TOKEN=""
ADMIN_TOKEN_IS_NEW=false

if [ -n "$EXISTING_TOKEN" ]; then
  HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Token token=${EXISTING_TOKEN}" \
    "$ZAMMAD_BASE_URL/api/v1/users" 2>/dev/null)
  if [ "$HTTP_STATUS" = "200" ]; then
    ADMIN_TOKEN="$EXISTING_TOKEN"
    green "Reusing existing admin token from dev/.env."
  else
    yellow "Existing token is invalid (HTTP $HTTP_STATUS) — creating a new one."
  fi
fi

if [ -z "$ADMIN_TOKEN" ]; then
  echo "Creating admin API token..."
  BASIC_AUTH=$(echo -n "$ADMIN_LOGIN:$ADMIN_PASSWORD" | base64 | tr -d '\n')
  PAT_RESPONSE=$(curl -sf -X POST \
    -H "Authorization: Basic $BASIC_AUTH" \
    -H "Content-Type: application/json" \
    "$ZAMMAD_BASE_URL/api/v1/user_access_token" \
    -d '{"name":"local-setup","permission":["admin","ticket.agent","ticket.customer"]}') \
    || die "Could not create admin PAT. Is Zammad fully initialized?"
  ADMIN_TOKEN=$(json_field "$PAT_RESPONSE" "token")
  [ -n "$ADMIN_TOKEN" ] || die "Could not extract token from: $PAT_RESPONSE"

  echo "Verifying token..."
  VERIFY_ELAPSED=0
  until [ "$(curl -s -o /dev/null -w '%{http_code}' \
      -H "Authorization: Token token=${ADMIN_TOKEN}" \
      "$ZAMMAD_BASE_URL/api/v1/users" 2>/dev/null)" = "200" ]; do
    if [ $VERIFY_ELAPSED -ge 30 ]; then
      die "New admin token not accepted after 30s — something is wrong."
    fi
    sleep 3
    VERIFY_ELAPSED=$((VERIFY_ELAPSED + 3))
  done
  green "Admin token created and verified."
  ADMIN_TOKEN_IS_NEW=true
fi

if [ "$ADMIN_TOKEN_IS_NEW" = "true" ]; then
  update_env_var "ZAMMAD_URL" "$ZAMMAD_BASE_URL"
  update_env_var "ZAMMAD_TOKEN" "$ADMIN_TOKEN"
fi
export ZAMMAD_TOKEN="$ADMIN_TOKEN"
export ZAMMAD_URL="$ZAMMAD_BASE_URL"
echo ""

# ── Phase 1: Full config bootstrap ───────────────────────────────────────────

echo ""
bold "Phase 1 — Full config bootstrap"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ROLES_RESPONSE=$(api GET /api/v1/roles 2>/dev/null || echo "[]")
if echo "$ROLES_RESPONSE" | python3 -c "import sys,json; roles=json.load(sys.stdin); exit(0 if any(r.get('name')=='Legal Admin' for r in roles) else 1)" 2>/dev/null; then
  yellow "Legal Admin role already exists — skipping Phase 1 (config already applied)."
else
  bash "$SCRIPT_DIR/configure-all.sh"
fi

# ── Phase 2: Local wiring ─────────────────────────────────────────────────────

echo ""
bold "Phase 2 — Local wiring"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Email notification channel..."
rails_runner "
UserInfo.current_user_id = 1
if Channel.exists?(area: 'Email::Notification')
  puts '  already exists — skipping.'
else
  ch = Channel.new
  ch.area = 'Email::Notification'
  ch.active = true
  ch.options = { 'outbound' => { 'adapter' => 'sendmail', 'options' => {} }, 'inbound' => {} }
  ch.preferences = {}
  ch.save!
  Rails.cache.clear
  puts '  created (id=' + ch.id.to_s + ').'
end
" | grep -v 'ActionCable\|INFO'

echo ""
echo "Bot user..."
ALL_USERS=$(api GET "/api/v1/users" 2>/dev/null || echo "[]")
BOT_USER_ID=$(echo "$ALL_USERS" | python3 -c "
import sys, json
users = json.load(sys.stdin)
matches = [u for u in users if u.get('login') == '$BOT_LOGIN' or u.get('email') == '$BOT_LOGIN']
print(matches[0]['id'] if matches else '')
" 2>/dev/null)

if [ -n "$BOT_USER_ID" ]; then
  yellow "  Bot user already exists (id=$BOT_USER_ID) — skipping."
else
  echo "  Creating bot user $BOT_LOGIN..."
  AGENT_ROLE_ID=$(api GET /api/v1/roles | python3 -c "
import sys,json
roles=json.load(sys.stdin)
match=[r['id'] for r in roles if r.get('name')=='Agent']
print(match[0] if match else 2)
" 2>/dev/null)
  BOT_JSON=$(printf '{"login":"%s","firstname":"%s","lastname":"%s","email":"%s","password":"%s","role_ids":[%s],"active":true}' \
    "$BOT_LOGIN" "$BOT_NAME_FIRST" "$BOT_NAME_LAST" "$BOT_LOGIN" "$BOT_PASSWORD" "$AGENT_ROLE_ID")
  CREATE_BOT=$(api POST /api/v1/users "$BOT_JSON")
  BOT_USER_ID=$(json_field "$CREATE_BOT" "id")
  [ -n "$BOT_USER_ID" ] || die "Failed to create bot user. Response: $CREATE_BOT"
  green "  Bot user created (id=$BOT_USER_ID)"
fi

# ── Bot PAT ───────────────────────────────────────────────────────────────────

ROOT_ENV="$ROOT_DIR/.env"
EXISTING_BOT_RAW=$(grep "^ZAMMAD_LEGAL_USER_TOKEN=" "$ROOT_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"')
EXISTING_BOT_RAW="${EXISTING_BOT_RAW#Token token=}"
BOT_TOKEN=""
BOT_TOKEN_IS_NEW=false

if [ -n "$EXISTING_BOT_RAW" ]; then
  HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Token token=${EXISTING_BOT_RAW}" \
    "$ZAMMAD_BASE_URL/api/v1/users/$BOT_USER_ID" 2>/dev/null)
  if [ "$HTTP_STATUS" = "200" ]; then
    BOT_TOKEN="$EXISTING_BOT_RAW"
    yellow "  Reusing existing bot token from legal-intake/.env."
  else
    yellow "  Existing bot token invalid (HTTP $HTTP_STATUS) — creating new one."
  fi
fi

if [ -z "$BOT_TOKEN" ]; then
  echo "  Creating PAT for bot user..."
  BOT_BASIC=$(echo -n "$BOT_LOGIN:$BOT_PASSWORD" | base64 | tr -d '\n')
  BOT_PAT_RESP=$(curl -sf -X POST \
    -H "Authorization: Basic $BOT_BASIC" \
    -H "Content-Type: application/json" \
    "$ZAMMAD_BASE_URL/api/v1/user_access_token" \
    -d '{"name":"legal-agent-local","permission":["ticket.agent"]}') \
    || die "Failed to create bot PAT. Is the bot user active?"
  BOT_TOKEN=$(json_field "$BOT_PAT_RESP" "token")
  [ -n "$BOT_TOKEN" ] || die "Could not extract bot token from: $BOT_PAT_RESP"
  green "  Bot PAT created."
  BOT_TOKEN_IS_NEW=true
fi

# ── Webhook ───────────────────────────────────────────────────────────────────

echo ""
echo "Webhook..."
WEBHOOKS_RESP=$(api GET /api/v1/webhooks 2>/dev/null || echo "[]")
WEBHOOK_ID=$(echo "$WEBHOOKS_RESP" | python3 -c "
import sys, json
whs = json.load(sys.stdin)
match = [w for w in whs if w.get('name') == '$WEBHOOK_NAME']
print(match[0]['id'] if match else '')
" 2>/dev/null)

WH_JSON=$(printf '{"name":"%s","endpoint":"%s","signature_token":"%s","ssl_verify":false,"active":true}' \
  "$WEBHOOK_NAME" "$WEBHOOK_ENDPOINT" "$ZAMMAD_WEBHOOK_SECRET")

if [ -n "$WEBHOOK_ID" ]; then
  api PUT "/api/v1/webhooks/$WEBHOOK_ID" "$WH_JSON" > /dev/null
  green "  Webhook updated (id=$WEBHOOK_ID) → $WEBHOOK_ENDPOINT"
else
  echo "  Creating webhook pointing to $WEBHOOK_ENDPOINT..."
  CREATE_WH=$(api POST /api/v1/webhooks "$WH_JSON")
  WEBHOOK_ID=$(json_field "$CREATE_WH" "id")
  [ -n "$WEBHOOK_ID" ] || die "Failed to create webhook. Response: $CREATE_WH"
  green "  Webhook created (id=$WEBHOOK_ID)"
fi

# ── Triggers ──────────────────────────────────────────────────────────────────

echo ""
echo "Triggers..."
TRIGGERS_JSON="$ZAMMAD_REPO/zammad-config/local/zammad-triggers.json"
TRIGGERS_BAK="/tmp/zammad-triggers.json.bak.$$"

cp "$TRIGGERS_JSON" "$TRIGGERS_BAK"
sed -i '' \
  "s/\"LEGAL_AGENT_BOT_USER_ID\"/\"$BOT_USER_ID\"/g; \
   s/LEGAL_AGENT_BOT_USER_ID/$BOT_USER_ID/g; \
   s/\"LEGAL_AGENT_WEBHOOK_ID\"/\"$WEBHOOK_ID\"/g; \
   s/LEGAL_AGENT_WEBHOOK_ID/$WEBHOOK_ID/g" \
  "$TRIGGERS_JSON"

ZAMMAD_LOCAL_URL="$ZAMMAD_BASE_URL" ZAMMAD_LOCAL_TOKEN="$ADMIN_TOKEN" \
  pnpm --dir "$ZAMMAD_REPO" exec tsx "$ZAMMAD_REPO/scripts/configure-zammad-local-triggers.ts"

cp "$TRIGGERS_BAK" "$TRIGGERS_JSON"
rm -f "$TRIGGERS_BAK"
green "  Triggers applied."

# ── Sync Supabase users → Zammad ──────────────────────────────────────────────
# Creates every user in legal-intake's local Supabase as a Zammad customer/agent
# so that ticket submission works without needing SSO. Idempotent — skips users
# that already exist in Zammad (matched by email). Also writes zammad_user_id
# back to Supabase so legal-intake knows the mapping.

echo ""
echo "Syncing Supabase users to Zammad..."

SUPABASE_URL=$(grep "^NEXT_PUBLIC_SUPABASE_URL=" "$ROOT_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"')
SUPABASE_SERVICE_KEY=$(grep "^SUPABASE_SERVICE_ROLE_KEY=" "$ROOT_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"')

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SERVICE_KEY" ]; then
  yellow "  Skipping user sync — NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set in legal-intake/.env."
else
  # Fetch Zammad role IDs once
  ZAMMAD_ROLES=$(api GET /api/v1/roles 2>/dev/null || echo "[]")
  ROLE_ADMIN=$(echo "$ZAMMAD_ROLES"   | python3 -c "import json,sys; r=json.load(sys.stdin); print(next((x['id'] for x in r if x['name']=='Admin'),1))")
  ROLE_AGENT=$(echo "$ZAMMAD_ROLES"   | python3 -c "import json,sys; r=json.load(sys.stdin); print(next((x['id'] for x in r if x['name']=='Agent'),2))")
  ROLE_CUSTOMER=$(echo "$ZAMMAD_ROLES" | python3 -c "import json,sys; r=json.load(sys.stdin); print(next((x['id'] for x in r if x['name']=='Customer'),3))")

  # Fetch all users from Supabase
  LI_USERS=$(curl -sf \
    -H "apikey: $SUPABASE_SERVICE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
    "$SUPABASE_URL/rest/v1/users?select=id,email,full_name,role,zammad_user_id" \
    2>/dev/null || echo "[]")

  USER_COUNT=$(echo "$LI_USERS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
  echo "  Found $USER_COUNT user(s) in Supabase."

  echo "$LI_USERS" | python3 -c "
import json, sys, subprocess, os, urllib.request, urllib.error

users = json.load(sys.stdin)
zammad_url = '${ZAMMAD_BASE_URL}'
token = '${ADMIN_TOKEN}'
supabase_url = '${SUPABASE_URL}'
service_key = '${SUPABASE_SERVICE_KEY}'
role_admin, role_agent, role_customer = ${ROLE_ADMIN}, ${ROLE_AGENT}, ${ROLE_CUSTOMER}

ROLE_MAP = {
  'legal_admin': [role_admin, role_agent],
  'legal_user':  [role_agent],
  'end_user':    [role_customer],
}

def zammad_req(method, path, body=None):
  url = zammad_url.rstrip('/') + path
  data = json.dumps(body).encode() if body else None
  req = urllib.request.Request(url, data=data, method=method,
    headers={'Authorization': f'Token token={token}', 'Content-Type': 'application/json', 'Accept': 'application/json'})
  try:
    with urllib.request.urlopen(req) as r:
      return json.loads(r.read())
  except urllib.error.HTTPError as e:
    return json.loads(e.read())

def supabase_patch(user_id, zammad_id):
  url = supabase_url.rstrip('/') + '/rest/v1/users?id=eq.' + user_id
  data = json.dumps({'zammad_user_id': zammad_id}).encode()
  req = urllib.request.Request(url, data=data, method='PATCH',
    headers={'apikey': service_key, 'Authorization': f'Bearer {service_key}',
             'Content-Type': 'application/json', 'Prefer': 'return=minimal'})
  try:
    with urllib.request.urlopen(req): pass
  except: pass

for u in users:
  email = u.get('email', '')
  full_name = (u.get('full_name') or email).strip()
  parts = full_name.split(' ', 1)
  firstname = parts[0]
  lastname = parts[1] if len(parts) > 1 else ''
  role_ids = ROLE_MAP.get(u.get('role', 'end_user'), [role_customer])

  if u.get('zammad_user_id'):
    print(f'  already synced: {email} (zammad_id={u[\"zammad_user_id\"]})')
    continue

  # Check if user already exists in Zammad
  import urllib.parse
  search = zammad_req('GET', f'/api/v1/users/search?query=email:{urllib.parse.quote(email)}&limit=1')
  existing_id = search[0]['id'] if isinstance(search, list) and search else None

  if existing_id:
    zammad_req('PUT', f'/api/v1/users/{existing_id}', {'role_ids': role_ids, 'firstname': firstname, 'lastname': lastname})
    supabase_patch(u['id'], existing_id)
    print(f'  linked existing: {email} (zammad_id={existing_id})')
  else:
    created = zammad_req('POST', '/api/v1/users', {
      'email': email, 'login': email,
      'firstname': firstname, 'lastname': lastname,
      'role_ids': role_ids, 'active': True,
      'note': 'Provisioned by local setup.sh'
    })
    zammad_id = created.get('id')
    if zammad_id:
      supabase_patch(u['id'], zammad_id)
      print(f'  created: {email} (zammad_id={zammad_id})')
    else:
      print(f'  failed: {email} — {created.get(\"error\", created)}')
" 2>/dev/null
  green "  User sync done."
fi

# ── Phase 3: Write to legal-intake/.env ──────────────────────────────────────

echo ""
bold "Phase 3 — Updating legal-intake/.env..."

update_root_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$ROOT_ENV" 2>/dev/null; then
    sed -i '' "s|^${key}=.*|${key}=\"${value}\"|" "$ROOT_ENV"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$ROOT_ENV"
  fi
}

# Always sync all Zammad values to legal-intake/.env — even when reusing existing
# tokens — so that restarting the old stack never leaves stale values behind.
update_root_env "ZAMMAD_URL" "$ZAMMAD_BASE_URL"
update_root_env "ZAMMAD_API_TOKEN" "$ADMIN_TOKEN"
update_root_env "ZAMMAD_LEGAL_USER_TOKEN" "$BOT_TOKEN"
update_root_env "ZAMMAD_LEGAL_USER_ID" "$BOT_USER_ID"
update_root_env "IS_LOCAL_ENVIRONMENT" "true"

green "legal-intake/.env updated."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bold "  Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Zammad UI   →  http://localhost:3001"
echo "  Admin login →  $ADMIN_LOGIN"
echo "  Mode        →  $([ "$NATIVE_MODE" = "true" ] && echo "native (bin/dev)" || echo "Docker (containers)")"
echo ""
yellow "  ⚠  First-time only: run DB migration before using custom fields."
yellow "     Admin → Objects → Execute Migrations  (http://localhost:3001/#system/object-manager)"
if [ "$NATIVE_MODE" = "true" ]; then
  yellow "     Then re-run: npm run zammad:local:native:setup"
else
  yellow "     Then re-run: npm run zammad:local:setup"
fi
echo ""
echo "  Next step:"
green "  npm run zammad:local:dev   →  http://localhost:3000"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
