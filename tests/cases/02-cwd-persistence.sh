#!/usr/bin/env bash
CASE_NAME="02-cwd-persistence"
source "$(dirname "$0")/../lib/assert.sh"
source "$(dirname "$0")/../lib/helpers.sh"

session="cwd-$$"

shell_run "$session" 'cd /tmp' >/dev/null
pwd1=$(shell_run "$session" 'pwd')
assert_eq "pwd after cd /tmp" "/tmp" "$pwd1"

shell_run "$session" 'cd /var' >/dev/null
pwd2=$(shell_run "$session" 'pwd')
assert_eq "pwd after cd /var" "/var" "$pwd2"

# combined cd && pwd in one call
combo=$(shell_run "$session" 'cd /etc && pwd')
assert_eq "combined cd && pwd" "/etc" "$combo"

# next call sees /etc
pwd3=$(shell_run "$session" 'pwd')
assert_eq "cwd after combined" "/etc" "$pwd3"

shell_cleanup "$session"
finish
