#!/usr/bin/env bash
# run-tests.sh — orchestrate end-to-end tests against an apple/container VM.
#
# Steps:
#  1. Generate fresh ed25519 keypair (test-only)
#  2. Build apple/container image with sshd + that pubkey
#  3. Start container, get IP, wait for sshd
#  4. Write temp ~/.ssh/config-style file pointing to that IP w/ test key
#  5. Run all test cases under tests/cases/
#  6. Stop + remove container, cleanup

set -uo pipefail

KEEP_KEYS=0
KEEP_CONTAINER=0
for arg in "$@"; do
  case "$arg" in
    --keep-keys) KEEP_KEYS=1 ;;
    --keep-container) KEEP_CONTAINER=1 ;;
    -h|--help)
      sed -n '3,12p' "$0"; exit 0 ;;
  esac
done

cd "$(dirname "$0")"
TESTS_DIR="$(pwd)"
PROJECT_DIR="$(cd .. && pwd)"

KEY_DIR="$TESTS_DIR/.test-keys"
KEY_FILE="$KEY_DIR/id_ed25519"
PUB_FILE="$KEY_DIR/id_ed25519.pub"
SSH_CONFIG_FILE="$TESTS_DIR/.test-ssh-config"
IMAGE_NAME="remote-launcher-test:latest"
CTR_NAME="rl-test-$(date +%s)"

mkdir -p "$KEY_DIR"

# ---------- 0. Prereqs ----------
echo "[run-tests] checking prerequisites"
command -v container >/dev/null || { echo "FATAL: apple/container not installed; see tests/README.md" >&2; exit 1; }
command -v jq        >/dev/null || { echo "FATAL: jq not installed (brew install jq)" >&2; exit 1; }
command -v ssh-keygen >/dev/null || { echo "FATAL: ssh-keygen not in PATH"; exit 1; }
[[ -x "$PROJECT_DIR/bin/ssh-shell" ]] || { echo "FATAL: $PROJECT_DIR/bin/ssh-shell missing"; exit 1; }

# Make sure container service is up
if ! container system status >/dev/null 2>&1; then
  echo "[run-tests] starting container system service"
  container system start || { echo "FATAL: container system start failed"; exit 1; }
fi

# ---------- 1. Keypair ----------
if [[ ! -f "$KEY_FILE" ]]; then
  echo "[run-tests] generating test keypair (ed25519)"
  ssh-keygen -t ed25519 -N "" -f "$KEY_FILE" -C "remote-launcher-test" >/dev/null
fi
[[ -f "$PUB_FILE" ]] || { echo "FATAL: missing pubkey at $PUB_FILE"; exit 1; }

# ---------- 2. Build image ----------
echo "[run-tests] building image $IMAGE_NAME"
PUBKEY_CONTENT=$(cat "$PUB_FILE")
# apple/container build syntax: container build -t <tag> --build-arg ... -f <Dockerfile> <context>
container build \
  -t "$IMAGE_NAME" \
  --build-arg "SSH_PUBKEY=$PUBKEY_CONTENT" \
  -f "$TESTS_DIR/Dockerfile.test-vm" \
  "$TESTS_DIR" >/dev/null || { echo "FATAL: container build failed"; exit 1; }

# ---------- 3. Run container ----------
echo "[run-tests] starting container $CTR_NAME"
container run -d --name "$CTR_NAME" "$IMAGE_NAME" >/dev/null \
  || { echo "FATAL: container run failed"; exit 1; }

# Cleanup trap
cleanup() {
  if [[ "$KEEP_CONTAINER" -eq 0 ]]; then
    echo "[run-tests] cleanup: removing container $CTR_NAME"
    container rm -f "$CTR_NAME" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_KEYS" -eq 0 ]]; then
    rm -f "$KEY_FILE" "$PUB_FILE"
    rm -rf "$KEY_DIR"/*  # leave .gitkeep
    touch "$KEY_DIR/.gitkeep"
  fi
  rm -f "$SSH_CONFIG_FILE"
  # purge wrapper state
  rm -rf "${TMPDIR:-/tmp}"/remote-launcher-*-$$* 2>/dev/null || true
}
trap cleanup EXIT

# Get container IP
# apple/container 0.11.x: ID lives at .configuration.id; IP at .networks[0].ipv4Address with "/24" suffix.
echo "[run-tests] waiting for IP"
VM_IP=""
for i in {1..20}; do
  VM_IP=$(container ls --format json 2>/dev/null \
    | jq -r --arg n "$CTR_NAME" '.[] | select(.configuration.id==$n) | .networks[0].ipv4Address // empty' \
    | head -n1 | sed 's|/.*||')
  [[ -n "$VM_IP" && "$VM_IP" != "null" ]] && break
  sleep 0.5
done
[[ -n "$VM_IP" && "$VM_IP" != "null" ]] || { echo "FATAL: could not resolve IP for $CTR_NAME"; exit 1; }
echo "[run-tests] container IP: $VM_IP"

# Write temp SSH config
cat > "$SSH_CONFIG_FILE" <<SSHCFG
Host rl-test
  HostName $VM_IP
  User testuser
  Port 22
  IdentityFile $KEY_FILE
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
SSHCFG

# Wait for sshd
echo "[run-tests] waiting for sshd on $VM_IP"
for i in {1..30}; do
  if ssh -F "$SSH_CONFIG_FILE" -o ConnectTimeout=2 -o BatchMode=yes rl-test 'echo ready' >/dev/null 2>&1; then
    echo "[run-tests] sshd ready (after ${i}s)"
    break
  fi
  sleep 1
  if [[ $i -eq 30 ]]; then
    echo "FATAL: sshd not ready after 30s"; exit 1
  fi
done

# ---------- 4. Run cases ----------
export VM_HOST="rl-test"
export SSH_SHELL="$PROJECT_DIR/bin/ssh-shell"
export SSH_CONFIG_FILE

echo
echo "================================================================"
echo "Running test cases"
echo "================================================================"
case_pass=0
case_fail=0
for case_file in "$TESTS_DIR"/cases/*.sh; do
  echo
  echo "--- $(basename "$case_file") ---"
  if bash "$case_file"; then
    case_pass=$((case_pass+1))
  else
    case_fail=$((case_fail+1))
  fi
done

echo
echo "================================================================"
echo "Test summary: $case_pass cases passed, $case_fail cases failed"
echo "================================================================"
[[ $case_fail -eq 0 ]] && exit 0 || exit 1
