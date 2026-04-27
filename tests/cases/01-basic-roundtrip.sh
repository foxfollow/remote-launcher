#!/usr/bin/env bash
CASE_NAME="01-basic-roundtrip"
source "$(dirname "$0")/../lib/assert.sh"
source "$(dirname "$0")/../lib/helpers.sh"

session="rt-$$"

mac_host=$(hostname)
vm_host=$(shell_run "$session" 'hostname')
assert_neq "hostname differs (Mac vs VM)" "$mac_host" "$vm_host"

# id should be testuser, not your Mac user
vm_whoami=$(shell_run "$session" 'whoami')
assert_eq "remote whoami=testuser" "testuser" "$vm_whoami"

shell_cleanup "$session"
finish
