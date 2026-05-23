#!/usr/bin/env bash
# manual-multi-vm.sh — spin up N containers (default 2) as distinct SSH hosts
# for manual exploration of remote-launcher's multi-host mode. Unlike
# run-tests.sh (which exits when assertions finish), this script leaves the
# containers running and prints the exact `remote-launcher` invocation to use.
#
# Usage:
#   tests/manual-multi-vm.sh            # 2 containers (mh-vm-1, mh-vm-2)
#   tests/manual-multi-vm.sh 3          # 3 containers (mh-vm-1, mh-vm-2, mh-vm-3)
#   tests/manual-multi-vm.sh 4          # any N up to 9
#   tests/manual-multi-vm.sh --down     # tear down everything this script created
#
# What it does:
#   1. Generates a fresh ed25519 keypair under tests/.test-keys (reused across runs)
#   2. Builds the test image (cached after the first run)
#   3. Boots N containers named mh-vm-1 .. mh-vm-N
#   4. Writes ~/.ssh/config.d/remote-launcher-manual with one alias per VM
#      (or a single combined file at tests/.manual-ssh-config if you don't
#      want to touch ~/.ssh — the script prints both options)
#   5. Prints the `remote-launcher` command to copy-paste
#
# After you're done: `tests/manual-multi-vm.sh --down`

set -uo pipefail

cd "$(dirname "$0")" || exit 1
TESTS_DIR="$(pwd)"
PROJECT_DIR="$(cd .. && pwd)"

KEY_DIR="$TESTS_DIR/.test-keys"
KEY_FILE="$KEY_DIR/id_ed25519"
PUB_FILE="$KEY_DIR/id_ed25519.pub"
SSH_CONFIG_FILE="$TESTS_DIR/.manual-ssh-config"
IMAGE_NAME="remote-launcher-test:latest"
NAME_PREFIX="mh-vm"

cmd_down() {
  echo "[manual-multi-vm] tearing down containers matching ${NAME_PREFIX}-*"
  # apple/container ls --format json gives us the names.
  ids=$(container ls -a --format json 2>/dev/null \
    | jq -r --arg p "$NAME_PREFIX-" '.[] | select(.configuration.id | startswith($p)) | .configuration.id')
  if [[ -z "$ids" ]]; then
    echo "[manual-multi-vm] (none running)"
  else
    while read -r id; do
      [[ -z "$id" ]] && continue
      echo "[manual-multi-vm]   removing $id"
      container rm -f "$id" >/dev/null 2>&1 || true
    done <<< "$ids"
  fi
  rm -f "$SSH_CONFIG_FILE"
  rm -rf "${TMPDIR:-/tmp}"/remote-launcher-*-mh-* 2>/dev/null || true
  echo "[manual-multi-vm] done"
}

case "${1:-}" in
  --down|-d|down)
    cmd_down; exit 0 ;;
  -h|--help)
    sed -n '3,22p' "$0"; exit 0 ;;
esac

N="${1:-2}"
if ! [[ "$N" =~ ^[0-9]+$ ]] || [[ "$N" -lt 1 || "$N" -gt 9 ]]; then
  echo "FATAL: N must be between 1 and 9 (got '$N')" >&2; exit 1
fi

# ---------- prereqs ----------
command -v container  >/dev/null || { echo "FATAL: apple/container not installed; see tests/README.md" >&2; exit 1; }
command -v jq         >/dev/null || { echo "FATAL: jq not installed (brew install jq)" >&2; exit 1; }
command -v ssh-keygen >/dev/null || { echo "FATAL: ssh-keygen not in PATH" >&2; exit 1; }
[[ -x "$PROJECT_DIR/bin/remote-launcher" ]] || { echo "FATAL: $PROJECT_DIR/bin/remote-launcher not executable" >&2; exit 1; }

if ! container system status >/dev/null 2>&1; then
  echo "[manual-multi-vm] starting container system service"
  container system start || { echo "FATAL: container system start failed" >&2; exit 1; }
fi

mkdir -p "$KEY_DIR"

# ---------- keypair ----------
if [[ ! -f "$KEY_FILE" ]]; then
  echo "[manual-multi-vm] generating test keypair (ed25519)"
  ssh-keygen -t ed25519 -N "" -f "$KEY_FILE" -C "remote-launcher-manual" >/dev/null
fi

# ---------- image ----------
echo "[manual-multi-vm] (re)building image $IMAGE_NAME"
PUBKEY_CONTENT=$(cat "$PUB_FILE")
container build \
  -t "$IMAGE_NAME" \
  --build-arg "SSH_PUBKEY=$PUBKEY_CONTENT" \
  -f "$TESTS_DIR/Dockerfile.test-vm" \
  "$TESTS_DIR" >/dev/null || { echo "FATAL: container build failed" >&2; exit 1; }

# ---------- tear down any previous run with the same prefix ----------
prev=$(container ls -a --format json 2>/dev/null \
  | jq -r --arg p "$NAME_PREFIX-" '.[] | select(.configuration.id | startswith($p)) | .configuration.id')
if [[ -n "$prev" ]]; then
  echo "[manual-multi-vm] removing previous containers"
  while read -r id; do
    [[ -z "$id" ]] && continue
    container rm -f "$id" >/dev/null 2>&1 || true
  done <<< "$prev"
fi

# ---------- start N containers ----------
declare -a NAMES=()
for i in $(seq 1 "$N"); do
  name="${NAME_PREFIX}-${i}"
  echo "[manual-multi-vm] starting $name"
  container run -d --name "$name" "$IMAGE_NAME" >/dev/null \
    || { echo "FATAL: failed to start $name" >&2; cmd_down; exit 1; }
  NAMES+=("$name")
done

# ---------- collect IPs ----------
declare -a IPS=()
for name in "${NAMES[@]}"; do
  ip=""
  for _ in $(seq 1 30); do
    ip=$(container ls --format json 2>/dev/null \
      | jq -r --arg n "$name" '.[] | select(.configuration.id==$n) | .networks[0].ipv4Address // empty' \
      | head -n1 | sed 's|/.*||')
    [[ -n "$ip" && "$ip" != "null" ]] && break
    sleep 0.5
  done
  [[ -n "$ip" && "$ip" != "null" ]] || { echo "FATAL: no IP for $name" >&2; cmd_down; exit 1; }
  IPS+=("$ip")
  echo "[manual-multi-vm]   $name → $ip"
done

# ---------- write SSH config ----------
: > "$SSH_CONFIG_FILE"
for i in $(seq 0 $((N-1))); do
  cat >> "$SSH_CONFIG_FILE" <<SSHCFG
Host ${NAMES[i]}
  HostName ${IPS[i]}
  User testuser
  Port 22
  IdentityFile $KEY_FILE
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR

SSHCFG
done

# ---------- wait for sshd on each ----------
for i in $(seq 0 $((N-1))); do
  echo "[manual-multi-vm] waiting for sshd on ${NAMES[i]} (${IPS[i]})"
  ready=0
  for _ in $(seq 1 30); do
    if ssh -F "$SSH_CONFIG_FILE" -o ConnectTimeout=2 -o BatchMode=yes "${NAMES[i]}" 'echo ready' >/dev/null 2>&1; then
      ready=1; break
    fi
    sleep 1
  done
  [[ "$ready" -eq 1 ]] || { echo "FATAL: sshd on ${NAMES[i]} never came up" >&2; cmd_down; exit 1; }
done

# ---------- print invocation ----------
HOST_FLAGS=""
for i in $(seq 1 $((N-1))); do
  HOST_FLAGS+=" --host ${NAMES[i]}"
done

cat <<EOF

================================================================
$N container(s) up. Containers persist until you tear them down.
================================================================

To launch a SINGLE Claude session against all $N hosts, point
\$HOME/.ssh/config at our generated config (or use -F directly):

  export GIT_SSH_COMMAND="ssh -F $SSH_CONFIG_FILE"   # not strictly needed
  ssh -F $SSH_CONFIG_FILE ${NAMES[0]} hostname        # smoke test
EOF

if [[ "$N" -eq 1 ]]; then
  cat <<EOF

  # Single-host launch:
  remote-launcher ${NAMES[0]}

EOF
else
  cat <<EOF

Because remote-launcher invokes \`ssh\` without \`-F\`, you have two options:

  (A) Append the manual config to your real ~/.ssh/config:
      cat $SSH_CONFIG_FILE >> ~/.ssh/config
      remote-launcher ${NAMES[0]}$HOST_FLAGS

  (B) Wrap with VM_SSH_OPTS so ssh-shell uses our config (no ~/.ssh edit):
      VM_SSH_OPTS="-F $SSH_CONFIG_FILE" \\
        remote-launcher ${NAMES[0]}$HOST_FLAGS

Inside Claude, route Bash by prefixing with @<host>:
EOF
  for n in "${NAMES[@]}"; do echo "  @${n} hostname"; done
  cat <<EOF

Try also:
  hostname                        # → ${NAMES[0]} (default)
  @nonexistent ls                 # → unknown host error (no dispatch)
  @${NAMES[0]} cd /tmp && pwd     # cwd persists per host
  @${NAMES[1]} pwd                # /home/testuser, NOT /tmp

EOF
fi

cat <<EOF
Tear down when done:
  $0 --down

Generated SSH config: $SSH_CONFIG_FILE
EOF
