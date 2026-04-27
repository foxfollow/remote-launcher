# Tests

End-to-end test harness for `remote-launcher`. Uses [apple/container](https://github.com/apple/container) to spin up a real Linux micro-VM with sshd, generates a fresh ed25519 keypair just for the test, and exercises the launcher end-to-end.

## Requirements

- Apple Silicon Mac, macOS 26+
- `container` installed (`container system start` running)
- `jq` (for parsing `container ls` output)
- `ssh`, `ssh-keygen`, `bash` (built-in)

## Run

```bash
cd tests
./run-tests.sh
```

By default the harness:
1. Generates an ed25519 keypair in `tests/.test-keys/` (gitignored).
2. Builds image `remote-launcher-test:latest` from `Dockerfile.test-vm`.
3. Starts a container `rl-test-<timestamp>` and gets its IP.
4. Waits for sshd to accept connections.
5. Runs every script in `tests/cases/` in lexical order.
6. Stops and removes the container.
7. Optionally keeps test keys for inspection (`--keep-keys`).

## Test cases

| File | What it verifies |
|---|---|
| `01-basic-roundtrip.sh` | Bash command goes to VM (hostname differs) |
| `02-cwd-persistence.sh` | `cd` persists between calls |
| `03-heredoc-files.sh` | Files created via heredoc land on VM |
| `04-env-scrub.sh` | Anthropic env vars do NOT cross to VM |
| `05-no-agent-forwarding.sh` | SSH agent socket not exposed on VM |
| `06-multi-session-isolation.sh` | Two sessions have independent cwds |

Each case is a standalone bash script that sources `lib/assert.sh` and `lib/helpers.sh`.

## Adding a test

1. Create `cases/NN-name.sh` (NN = next number).
2. Source the lib helpers, use `$VM_HOST` (set by `run-tests.sh`) and `$SSH_SHELL` (path to wrapper).
3. End with `pass "test name"` or let `assert_*` fail.

## Cleanup

The harness stops/removes its container on exit (success or failure). To force-clean stragglers:

```bash
container ls -a --format json | jq -r '.[] | select(.configuration.id | startswith("rl-test")) | .configuration.id' | xargs -I{} container rm -f {}
container images rm remote-launcher-test:latest 2>/dev/null || true
rm -rf .test-keys/* .test-output/
```
