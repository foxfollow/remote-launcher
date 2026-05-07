#!/usr/bin/env bash
# 07-multi-host-routing — exercise @host prefix routing, per-host isolation,
# and the unknown-host error path.
#
# Strategy: we have one container, but ssh-shell only cares about the host
# *name*. Add a second SSH config alias that points to the same container,
# and treat the two aliases as if they were two distinct hosts. That exercises
# every ssh-shell code path that depends on host identity (per-host
# ControlMaster sockets, per-host cwd files, the @host prefix parser, the
# unknown-host error) without needing a second VM.

# shellcheck disable=SC1091
CASE_NAME="07-multi-host-routing"
source "$(dirname "$0")/../lib/assert.sh"
source "$(dirname "$0")/../lib/helpers.sh"

# Add a second alias for the same VM IP. We grab the resolved HostName from
# the existing $SSH_CONFIG_FILE so we don't have to know the IP ourselves.
VM_IP=$(awk '/HostName/ {print $2; exit}' "$SSH_CONFIG_FILE")
[[ -n "$VM_IP" ]] || { fail "could not extract HostName from $SSH_CONFIG_FILE"; finish; exit 1; }

EXTENDED_CFG="$(dirname "$SSH_CONFIG_FILE")/.test-ssh-config-multihost"
cp "$SSH_CONFIG_FILE" "$EXTENDED_CFG"
cat >> "$EXTENDED_CFG" <<SSHCFG

Host rl-test-b
  HostName $VM_IP
  User testuser
  Port 22
  IdentityFile $(awk '/IdentityFile/ {print $2; exit}' "$SSH_CONFIG_FILE")
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
SSHCFG

session="mh-$$"

# Helper: run ssh-shell in multi-host mode with rl-test (default) and rl-test-b.
mh_run() {
  local cmd="$1"
  VM_REMOTE_HOST="rl-test" \
  VM_REMOTE_HOSTS="rl-test rl-test-b" \
  VM_REMOTE_DEFAULT_HOST="rl-test" \
  VM_REMOTE_SHELLS="rl-test=posix:rl-test-b=posix" \
  VM_REMOTE_SESSION="$session" \
  VM_SSH_OPTS="-F $EXTENDED_CFG" \
    "$SSH_SHELL" -c "$cmd"
}

# Routing — @rl-test-b should land via the second alias. Both should report
# the container's hostname (same VM), but the per-host state files should
# differ.
out_default=$(mh_run 'hostname')
out_b=$(mh_run '@rl-test-b hostname')
assert_eq        "default host hostname" "$out_default" "$out_b"   # same VM
assert_neq       "default host nonempty" "" "$out_default"

# Per-host cwd isolation — cd /tmp on default host must NOT change cwd on
# @rl-test-b. We cd /tmp on default, cd /var on @rl-test-b, then check pwd.
mh_run 'cd /tmp' >/dev/null
mh_run '@rl-test-b cd /var' >/dev/null
pwd_default=$(mh_run 'pwd')
pwd_b=$(mh_run '@rl-test-b pwd')
assert_eq "default host pwd=/tmp"      "/tmp"  "$pwd_default"
assert_eq "rl-test-b pwd=/var"          "/var"  "$pwd_b"

# Per-host state files should both exist with their own cwd contents.
state_dir="${TMPDIR:-/tmp}/remote-launcher-${session}"
[[ -f "$state_dir/cwd-rl-test"    ]] && pass "per-host cwd file: cwd-rl-test"   || fail "missing $state_dir/cwd-rl-test"
[[ -f "$state_dir/cwd-rl-test-b"  ]] && pass "per-host cwd file: cwd-rl-test-b" || fail "missing $state_dir/cwd-rl-test-b"

# Per-host ControlMaster sockets.
[[ -S "$HOME/.ssh/rl-${session}-rl-test.s"    ]] && pass "ControlMaster sock: rl-test"   || fail "missing rl-test ControlMaster socket"
[[ -S "$HOME/.ssh/rl-${session}-rl-test-b.s"  ]] && pass "ControlMaster sock: rl-test-b" || fail "missing rl-test-b ControlMaster socket"

# Unknown host — should fail with non-zero exit and a useful error, without
# dispatching anywhere. Capture stderr.
err_out=$(mh_run '@nonexistent ls /' 2>&1 >/dev/null) && unknown_rc=0 || unknown_rc=$?
assert_neq      "unknown host non-zero exit" "0" "$unknown_rc"
assert_contains "unknown host error mentions name" "@nonexistent" "$err_out"
assert_contains "unknown host lists available"     "rl-test-b"    "$err_out"

# Env scrubbing should still work on the routed host (regression check).
ANTHROPIC_API_KEY="dummy-must-not-leak" \
CLAUDE_CODE_OAUTH_TOKEN="dummy-must-not-leak" \
  remote_env=$(mh_run '@rl-test-b env')
assert_not_contains "no ANTHROPIC_API_KEY on @rl-test-b" "ANTHROPIC_API_KEY"      "$remote_env"
assert_not_contains "no CLAUDE_CODE_OAUTH_TOKEN on @rl-test-b" "CLAUDE_CODE_OAUTH_TOKEN" "$remote_env"

# Cleanup.
shell_cleanup "$session"
# Tear down ControlMasters for our two aliases (kept open by ControlPersist).
ssh -F "$EXTENDED_CFG" -o ControlPath="$HOME/.ssh/rl-${session}-rl-test.s"   -O exit rl-test    2>/dev/null || true
ssh -F "$EXTENDED_CFG" -o ControlPath="$HOME/.ssh/rl-${session}-rl-test-b.s" -O exit rl-test-b  2>/dev/null || true
rm -f "$EXTENDED_CFG"

finish
