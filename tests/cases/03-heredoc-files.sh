#!/usr/bin/env bash
CASE_NAME="03-heredoc-files"
source "$(dirname "$0")/../lib/assert.sh"
source "$(dirname "$0")/../lib/helpers.sh"

session="he-$$"
testfile="/tmp/rl-test-$$.txt"

shell_run "$session" "cat > $testfile <<'INNER_EOF'
line one
line two
\$HOME-should-stay-literal
INNER_EOF" >/dev/null

content=$(shell_run "$session" "cat $testfile")
assert_contains "file has line one" "line one" "$content"
assert_contains "file has line two" "line two" "$content"
assert_contains "literal \$HOME preserved (single-quoted heredoc)" '$HOME-should-stay-literal' "$content"
# Also explicitly verify no expansion happened
assert_not_contains "no expansion to /home/testuser" "/home/testuser-should-stay-literal" "$content"

shell_run "$session" "rm -f $testfile" >/dev/null
shell_cleanup "$session"
finish
