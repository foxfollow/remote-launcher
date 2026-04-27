#!/usr/bin/env bash
CASE_NAME="04-env-scrub"
source "$(dirname "$0")/../lib/assert.sh"
source "$(dirname "$0")/../lib/helpers.sh"

session="es-$$"

# Inject canary credentials in OUR env. ssh-shell is invoked as a child;
# whether or not these survive into ssh, they should NOT appear on the VM
# because OpenSSH does not forward env vars unless SendEnv is configured
# (and we never configure it).
canary_api="LEAK_API_TOKEN_$(date +%s)"
canary_oauth="LEAK_OAUTH_TOKEN_$(date +%s)"

# Use env to set vars only for this single shell_run call
remote_env=$(
  ANTHROPIC_API_KEY="$canary_api" \
  CLAUDE_CODE_OAUTH_TOKEN="$canary_oauth" \
  shell_run "$session" 'env'
)

assert_not_contains "no ANTHROPIC_API_KEY on VM" "ANTHROPIC_API_KEY" "$remote_env"
assert_not_contains "no CLAUDE_CODE_OAUTH_TOKEN on VM" "CLAUDE_CODE_OAUTH_TOKEN" "$remote_env"
assert_not_contains "canary api value not on VM" "$canary_api" "$remote_env"
assert_not_contains "canary oauth value not on VM" "$canary_oauth" "$remote_env"

# Also: no Anthropic-prefixed vars at all
anthropic_count=$(echo "$remote_env" | grep -ciE '^(ANTHROPIC_|CLAUDE_CODE_)' || true)
assert_eq "no ANTHROPIC_*/CLAUDE_CODE_* vars on VM" "0" "$anthropic_count"

shell_cleanup "$session"
finish
