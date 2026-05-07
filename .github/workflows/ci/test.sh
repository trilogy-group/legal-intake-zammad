#!/usr/bin/env bash

set -o errexit
set -o pipefail

# shellcheck disable=SC1091
source /etc/profile.d/rvm.sh
# shellcheck disable=SC1091
source .gitlab/environment.env

echo "Checking assets generation…"
# Skip if assets cache was restored
if [ ! -d "public/assets" ] || [ ! -d "public/packs" ]; then
  bundle exec rake assets:precompile
else
  echo "Assets already cached, skipping precompile"
fi

# Only run frontend tests on first worker to avoid redundancy
if [ "${TEST_GROUP:-1}" = "1" ]; then
  echo "Running front end tests…"
  pnpm test
else
  echo "Skipping frontend tests (handled by worker 1)"
fi

echo "Running basic rspec tests in parallel (group ${TEST_GROUP:-1}/6)…"
bundle exec rake zammad:db:init
bundle exec parallel_rspec spec/ \
  -n 6 \
  --only-group "${TEST_GROUP:-1}" \
  --exclude-pattern "spec/system/**/*_spec.rb" \
  -o '-t ~searchindex -t ~integration -t ~required_envs -t ~pgp'

# Only run minitest on first worker to avoid redundancy
if [ "${TEST_GROUP:-1}" = "1" ]; then
  echo "Running basic minitest tests…"
  bundle exec rake zammad:db:reset
  bundle exec rake test:units
else
  echo "Skipping minitest (handled by worker 1)"
fi
