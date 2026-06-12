#!/usr/bin/env bash
# 08-wrapped-localhost-routing — regression test for @host prefix routing when
# the Bash tool command arrives in Claude Code's real wrapped form.
#
# Claude Code wraps the model's command in an eval marker, and since v2.1.173
# it also PREPENDS a prelude (snapshot sourcing + CLAUDE_CODE_VERSION export)
# before that marker:
#
#   source …/snapshot-bash-….sh 2>/dev/null || true && export CLAUDE_CODE_VERSION="…"
#   : && shopt -u extglob 2>/dev/null || true && eval '<inner>' < /dev/null && pwd …
#
# The old parser anchored on CMD *starting* with `shopt … && eval '`, so the
# prelude made it skip @host routing entirely — `@localhost foo` reached the
# shell verbatim and died with "@localhost: not found". This test feeds the
# wrapped form through ssh-shell and asserts the prefix is stripped and routed.
#
# Routes only to `localhost`, so it needs NO VM/container — runnable standalone:
#   bash tests/cases/08-wrapped-localhost-routing.sh

# shellcheck disable=SC1091
CASE_NAME="08-wrapped-localhost-routing"
source "$(dirname "$0")/../lib/assert.sh"

SSH_SHELL="${SSH_SHELL:-$(cd "$(dirname "$0")/../../bin" && pwd)/ssh-shell}"
[[ -x "$SSH_SHELL" ]] || { fail "ssh-shell not executable at $SSH_SHELL"; finish; exit 1; }

session="wrap-$$"

# A real (empty) snapshot file, mirroring the Mac's localhost reality where the
# shell-snapshot the wrapper sources actually exists. (On the Mac, /bin/sh is
# bash in POSIX mode, where `source` of a *missing* file is a fatal special-
# builtin error — so a bogus path would abort the shell, unlike a dash remote.)
SNAPSHOT_FILE="${TMPDIR:-/tmp}/rl-test-snapshot-$$.sh"
: > "$SNAPSHOT_FILE"
trap 'rm -f "$SNAPSHOT_FILE"' EXIT

# Build the exact wrapper Claude Code v2.1.173 emits around <inner>.
wrap_cmd() {
  local inner="$1"
  # Escape single quotes in <inner> the bash way ('\'') just like Claude does.
  local esc="${inner//\'/\'\\\'\'}"
  printf '%s\n%s' \
    "source ${SNAPSHOT_FILE} 2>/dev/null || true && export CLAUDE_CODE_VERSION=\"2.1.173 (Claude Code)\"" \
    ": && shopt -u extglob 2>/dev/null || true && eval '${esc}' < /dev/null && pwd -P >| /tmp/claude-test-cwd"
}

# Run ssh-shell in multi-host mode with localhost as a routable host.
lh_run() {
  local cmd="$1"
  VM_REMOTE_HOST="localhost" \
  VM_REMOTE_HOSTS="localhost" \
  VM_REMOTE_DEFAULT_HOST="localhost" \
  VM_REMOTE_SHELLS="localhost=posix" \
  VM_REMOTE_SESSION="$session" \
    "$SSH_SHELL" -c "$cmd"
}

expected_whoami=$(whoami)

# 1. @localhost prefix on the WRAPPED command must route to the Mac and strip
#    the prefix — not leak "@localhost" to the shell.
out_prefixed=$(lh_run "$(wrap_cmd '@localhost whoami')" 2>&1)
assert_eq        "@localhost whoami routed locally" "$expected_whoami" "$out_prefixed"
assert_not_contains "no literal @localhost leak"    "@localhost"       "$out_prefixed"
assert_not_contains "no 'not found' from bad token" "not found"        "$out_prefixed"

# 2. Unprefixed wrapped command still works (default host = localhost).
out_default=$(lh_run "$(wrap_cmd 'whoami')" 2>&1)
assert_eq "unprefixed whoami routed locally" "$expected_whoami" "$out_default"

# 3. Embedded single quotes in the inner command survive the un-escape /
#    re-escape round-trip after the prefix is stripped.
out_quoted=$(lh_run "$(wrap_cmd "@localhost echo 'a'\''b'")" 2>&1)
assert_eq "@localhost preserves embedded quote" "a'b" "$out_quoted"

# 4. Unknown @host still fails loudly without dispatching.
err_unknown=$(lh_run "$(wrap_cmd '@nope whoami')" 2>&1) && rc=0 || rc=$?
assert_neq      "unknown host non-zero exit"     "0"      "$rc"
assert_contains "unknown host error names token" "@nope"  "$err_unknown"

# Cleanup per-session state.
rm -rf "${TMPDIR:-/tmp}/remote-launcher-${session}" 2>/dev/null || true

finish
