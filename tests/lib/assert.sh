# Minimal assertion lib.
# Requires CASE_NAME to be set by the calling case file.

set -uo pipefail

: "${CASE_NAME:?CASE_NAME must be set by case file}"

_pass=0
_fail=0

pass() {
  echo "  ✅ ${CASE_NAME}: $*"
  _pass=$((_pass+1))
}

fail() {
  echo "  ❌ ${CASE_NAME}: $*" >&2
  _fail=$((_fail+1))
}

assert_eq() {
  # assert_eq <name> <expected> <actual>
  local name="$1"; local exp="$2"; local act="$3"
  if [[ "$exp" == "$act" ]]; then pass "$name"
  else fail "$name (expected '$exp', got '$act')"; fi
}

assert_neq() {
  local name="$1"; local exp="$2"; local act="$3"
  if [[ "$exp" != "$act" ]]; then pass "$name"
  else fail "$name (expected NOT '$exp', got '$act')"; fi
}

assert_contains() {
  local name="$1"; local needle="$2"; local haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then pass "$name"
  else fail "$name (haystack lacks '$needle')"; fi
}

assert_not_contains() {
  local name="$1"; local needle="$2"; local haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then pass "$name"
  else fail "$name (haystack UNEXPECTEDLY contains '$needle')"; fi
}

# Print summary and set exit code via $? when sourced
finish() {
  echo "  --- ${CASE_NAME}: $_pass passed, $_fail failed"
  [[ $_fail -eq 0 ]]
}
