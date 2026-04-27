# Helpers used by case files.
# $VM_HOST, $SSH_SHELL, $SSH_CONFIG_FILE are set by run-tests.sh.

# Run an arbitrary command via the ssh-shell wrapper, with a unique session id.
# Captures stdout; echoes it. Honors VM_SSH_OPTS so tests can pass -F.
shell_run() {
  local session="${1:-default-$$}"
  shift
  local cmd="$*"
  VM_REMOTE_HOST="$VM_HOST" \
  VM_REMOTE_SESSION="$session" \
  VM_SSH_OPTS="-F $SSH_CONFIG_FILE" \
    "$SSH_SHELL" -c "$cmd"
}

# Cleanup wrapper state for a given session id.
shell_cleanup() {
  local session="${1:-default-$$}"
  rm -rf "${TMPDIR:-/tmp}/remote-launcher-${session}"
}
