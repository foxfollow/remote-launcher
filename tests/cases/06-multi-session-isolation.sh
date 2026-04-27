#!/usr/bin/env bash
CASE_NAME="06-multi-session-isolation"
source "$(dirname "$0")/../lib/assert.sh"
source "$(dirname "$0")/../lib/helpers.sh"

s1="iso-a-$$"
s2="iso-b-$$"

shell_run "$s1" 'cd /tmp' >/dev/null
shell_run "$s2" 'cd /var' >/dev/null

pwd_s1=$(shell_run "$s1" 'pwd')
pwd_s2=$(shell_run "$s2" 'pwd')

assert_eq "session A in /tmp" "/tmp" "$pwd_s1"
assert_eq "session B in /var" "/var" "$pwd_s2"

shell_cleanup "$s1"
shell_cleanup "$s2"
finish
