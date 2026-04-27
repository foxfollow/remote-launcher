#!/usr/bin/env bash
CASE_NAME="05-no-agent-forwarding"
source "$(dirname "$0")/../lib/assert.sh"
source "$(dirname "$0")/../lib/helpers.sh"

session="af-$$"

auth_sock=$(shell_run "$session" 'echo "${SSH_AUTH_SOCK:-empty}"')
assert_eq "SSH_AUTH_SOCK not set on VM" "empty" "$auth_sock"

# Also: no agent socket files in /tmp owned by testuser
sockets=$(shell_run "$session" 'find /tmp -maxdepth 2 -type s -name "agent.*" 2>/dev/null | wc -l')
assert_eq "no ssh-agent sockets visible on VM" "0" "$sockets"

shell_cleanup "$session"
finish
