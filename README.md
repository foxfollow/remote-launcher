# remote-launcher

Launch [Claude Code](https://www.anthropic.com/claude-code) on your Mac while transparently executing every Bash command on a remote Linux host via SSH. Anthropic credentials never touch the remote host.

## Why

The default Claude Code workflow for "operate on a remote box" is to install Claude Code on that box and SSH into it. That puts your OAuth token on a machine you may not fully control. `remote-launcher` keeps Claude (and your token) on the Mac, and ships only individual shell commands across SSH. Files created during a session live on the remote host where they're actually needed.

## Architecture

```
  ┌────────────────────────┐         ┌─────────────────────────┐
  │ Mac                    │         │ Remote VM               │
  │                        │         │                         │
  │ ┌────────────────────┐ │         │                         │
  │ │ Claude Code        │ │         │                         │
  │ │ ─ Read/Edit/Write ─┼─┼── Mac   │                         │
  │ │ ─ Bash tool ───────┼─┼─SSH────►│ /bin/bash → executes    │
  │ └────────────────────┘ │         │     here, files here    │
  │   ▲                    │         │                         │
  │   │ OAuth from keychain│         │                         │
  │   │ stays here         │         │                         │
  └───┴────────────────────┘         └─────────────────────────┘
```

- **Bash tool → VM** via `CLAUDE_CODE_SHELL` env var (officially supported by Claude Code 2.0.65+).
- **Read/Edit/Write tools → Mac.** A system-prompt addendum tells the model to use Bash heredoc for VM-side files.
- **Token isolation.** `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` strips Anthropic credentials from the bash subprocess environment before SSH runs.

## Requirements

- macOS (Apple Silicon recommended for the test harness; the launcher itself runs anywhere with `bash` + `ssh`)
- Claude Code 2.0.65 or later
- SSH key auth to your target host (no passwords, no agent forwarding by default)
- For tests: [apple/container](https://github.com/apple/container) (macOS 26+) and `jq`

## Install

```bash
git clone <this-repo> ~/code/remote-launcher
cd ~/code/remote-launcher
./install.sh
```

`install.sh` is non-destructive: it creates symlinks in `~/.local/bin/` and registers the skill in `~/.claude/skills/remote-launcher/`.

Make sure `~/.local/bin` is in your `PATH`.

## Use

```bash
remote-launcher myvm                                  # bare interactive
remote-launcher myvm --task ~/projects/demo/TASK.md   # pre-load a task
remote-launcher myvm -- --model claude-opus-4-7       # forward args to claude
```

A walkthrough of the simplest case (single agent installs nginx and
verifies) is in [`examples/single-agent.md`](examples/single-agent.md).

## Multi-agent

Multiple Claude sessions, each in its own terminal, all targeting the
same VM:

```bash
# Terminal 1 — init agent (sequential)
remote-launcher myvm --task ~/projects/demo/MASTER.md
# inside Claude: "You are Agent 0."

# Terminals 2 and 3 — workers (parallel)
remote-launcher myvm --task ~/projects/demo/MASTER.md   # × 2
# inside each: "You are Agent 1." / 2

# Terminal 4 — reviewer (sequential)
remote-launcher myvm --task ~/projects/demo/MASTER.md
# "You are Agent 3."

# Pull artifacts back
scp -r myvm:~/multi-demo ~/Downloads/
```

A complete worked example with a shared MASTER.md is in
[`examples/multi-agent.md`](examples/multi-agent.md).

## Security model

See [`docs/security-model.md`](docs/security-model.md). Short version:

| Concern | How it's handled |
|---|---|
| Anthropic OAuth on VM | macOS keychain only; `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` strips Anthropic env from subprocess env |
| Credentials in env passed via SSH | OpenSSH does not forward env unless `SendEnv` is set; we don't set it |
| SSH agent / key chaining | Agent forwarding off by default (no `-A`) |
| Credentials accidentally written to disk on VM | Files originate from bash heredocs *on the VM*; Mac-side never writes secret files |
| Connection theft after disconnect | `ControlPersist=15m`; the socket is in `$TMPDIR` of your Mac user only |

The full security model is verified by the test suite — see [`tests/`](tests/).

## Diagnostics

```bash
remote-launcher-doctor                # files / PATH check only
remote-launcher-doctor myvm           # also live SSH + wrapper round-trip
```

## Tests

```bash
cd tests
./run-tests.sh
```

The harness uses Apple's `container` to spin up an Ubuntu micro-VM with sshd, generates a fresh ed25519 keypair just for the test, and exercises the launcher against it. See [`tests/README.md`](tests/README.md).

## Limitations

- Interactive TUIs (`vim`, `htop`) on the VM may render poorly — the wrapper does not allocate a pty.
- Each shell call is a fresh remote shell; environment and aliases do not persist between calls. Working directory does (tracked via state file).
- No file sync. By design — files live on the VM. To pull artifacts: `scp -r myvm:path ~/local`.

## License

MIT. See [LICENSE](LICENSE).

## Security disclosures

See [SECURITY.md](SECURITY.md).
