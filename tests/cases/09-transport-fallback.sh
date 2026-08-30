#!/usr/bin/env bash
# 09-transport-fallback — regression test for hosts with no base64(1).
#
# The POSIX transport used to hard-require `base64 -d` on the remote host:
#
#   ssh host "/bin/sh -c 'printf %s <b64> | base64 -d | /bin/sh'"
#
# BusyBox firmware on consumer routers (ASUSWRT, OpenWrt) is routinely built
# without the base64 applet, and base FreeBSD has no base64(1) either. On such
# a host EVERY Bash call died — and worse, died silently: with the decoder
# missing, the trailing `/bin/sh` got empty stdin and exited 0, so the wrapper
# reported success while `base64: not found` came back as the command output.
#
# ssh-shell now probes the host once per session and falls back to a
# printf-octal encoding that needs only a shell builtin.
#
# Uses a fake `ssh` on PATH that runs the command locally, so it needs NO
# VM/container — runnable standalone:
#   bash tests/cases/09-transport-fallback.sh

# shellcheck disable=SC1091
CASE_NAME="09-transport-fallback"
source "$(dirname "$0")/../lib/assert.sh"

SSH_SHELL="${SSH_SHELL:-$(cd "$(dirname "$0")/../../bin" && pwd)/ssh-shell}"
[[ -x "$SSH_SHELL" ]] || { fail "ssh-shell not executable at $SSH_SHELL"; finish; exit 1; }

TMPROOT="${TMPDIR:-/tmp}/rl-xfer-test-$$"
BIN_DIR="$TMPROOT/bin"
MASK_DIR="$TMPROOT/mask"
mkdir -p "$BIN_DIR" "$MASK_DIR"
trap 'rm -rf "$TMPROOT"' EXIT

# Fake ssh: ignore the options and the host, run the last argument locally.
# Every ssh-shell call passes exactly one command string as the final arg.
cat > "$BIN_DIR/ssh" <<'SSHEOF'
#!/bin/sh
cmd=""
for a in "$@"; do cmd="$a"; done
if [ -n "${RL_TEST_MASK_DIR:-}" ]; then
  PATH="$RL_TEST_MASK_DIR:$PATH"
  export PATH
fi
exec /bin/sh -c "$cmd"
SSHEOF
chmod +x "$BIN_DIR/ssh"

# Stand-ins that fail the way a missing applet does, for the masked runs.
for tool in base64 openssl; do
  cat > "$MASK_DIR/$tool" <<'MASKEOF'
#!/bin/sh
echo "$(basename "$0"): not found" >&2
exit 127
MASKEOF
  chmod +x "$MASK_DIR/$tool"
done

PATH="$BIN_DIR:$PATH"
export PATH

# run <session> <command> — one ssh-shell call against the fake host.
run() {
  VM_REMOTE_HOST="fakehost" \
  VM_REMOTE_SESSION="$1" \
  VM_REMOTE_SHELL="posix" \
    "$SSH_SHELL" -c "$2"
}

xfer_mode() {
  cat "${TMPDIR:-/tmp}/remote-launcher-$1/xfer-fakehost" 2>/dev/null
}

drop_state() {
  rm -rf "${TMPDIR:-/tmp}/remote-launcher-$1" 2>/dev/null || true
}

expected_whoami=$(whoami)

# ---------------------------------------------------------------- no base64
sess="xfer-nob64-$$"
export RL_TEST_MASK_DIR="$MASK_DIR"

out=$(run "$sess" 'whoami' 2>&1)
assert_eq           "octal transport runs the command" "$expected_whoami" "$out"
assert_not_contains "no decoder error leaks through"   "not found"        "$out"
assert_eq           "probe picked the octal encoding"  "octal"            "$(xfer_mode "$sess")"

# The masking bug: a dead transport must NOT come back as exit 0.
run "$sess" 'exit 42' >/dev/null 2>&1; rc=$?
assert_eq "exit code survives the octal transport" "42" "$rc"

# Quotes, $, backticks and newlines must reach the remote shell untouched.
tricky=$(run "$sess" 'printf "%s\n" "a'\''b\$c\`d"' 2>&1)
assert_eq "octal transport is quoting-transparent" 'a'"'"'b$c`d' "$tricky"

# cwd still persists across calls.
run "$sess" 'cd /tmp' >/dev/null 2>&1
assert_eq "cwd persists under octal transport" "/tmp" "$(run "$sess" 'pwd' 2>&1)"

# Payload above XFER_CHUNK_MAX (60000) must stage in chunks, not truncate.
# 20000 chars of content → ~80000 chars of octal escapes.
big=$(printf 'x%.0s' $(seq 1 20000))
big_out=$(run "$sess" "printf %s '$big' | wc -c" 2>&1 | tr -d ' ')
assert_eq "oversized octal payload staged in chunks" "20000" "$big_out"
drop_state "$sess"

# ------------------------------------------------------------- with base64
sess="xfer-b64-$$"
unset RL_TEST_MASK_DIR

out=$(run "$sess" 'whoami' 2>&1)
assert_eq       "base64 transport runs the command"  "$expected_whoami" "$out"
assert_contains "probe picked a base64 decoder"      "base64:"          "$(xfer_mode "$sess")"

run "$sess" 'exit 7' >/dev/null 2>&1; rc=$?
assert_eq "exit code survives the base64 transport" "7" "$rc"

# ~100000 chars → base64 payload above the chunk ceiling as well.
big=$(printf 'y%.0s' $(seq 1 100000))
big_out=$(run "$sess" "printf %s '$big' | wc -c" 2>&1 | tr -d ' ')
assert_eq "oversized base64 payload staged in chunks" "100000" "$big_out"
drop_state "$sess"

finish
