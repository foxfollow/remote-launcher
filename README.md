# remote-launcher

[![ShellCheck](https://github.com/foxfollow/remote-launcher/actions/workflows/shellcheck.yml/badge.svg?branch=main)](https://github.com/foxfollow/remote-launcher/actions/workflows/shellcheck.yml)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-2.1.156-5A29E4)](https://code.claude.com/docs/en/changelog)
![os-macOS](https://img.shields.io/badge/OS-macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

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
git clone https://github.com/foxfollow/remote-launcher.git ~/code/remote-launcher
cd ~/code/remote-launcher
./install.sh
```

`install.sh` is non-destructive: it creates symlinks in `~/.local/bin/` and registers the skill in `~/.claude/skills/remote-launcher/`.

Make sure `~/.local/bin` is in your `PATH`.

## Use

```bash
remote-launcher myvm                                  # bare interactive
remote-launcher myvm --task ~/projects/demo/TASK.md   # pre-load a task
remote-launcher myvm --confirm-bash                   # require approval for every Bash call
remote-launcher myvm -pfp                             # auto-accept changed host fingerprint (after VM snapshot/rebuild)
remote-launcher winhost --shell powershell            # force PowerShell on the remote (default: auto-detect)
remote-launcher myvm -- --model claude-opus-4-7       # forward args to claude
```

**Remote shell flavor.** By default the launcher probes the host and picks
between POSIX (`/bin/sh`) and PowerShell (`pwsh` or `powershell`). When it
detects PowerShell, it loads a PowerShell-flavored system prompt so the
model writes `Get-Content` / `Set-Content` / `Select-String` instead of
`cat` / `grep` / `sed`, and runs commands via `-EncodedCommand` so quoting
stays sane. Override with `--shell posix|powershell` if auto-detect picks
wrong.

**Bash auto-approve.** By default the launcher passes
`--allowedTools 'Bash(*)'` to Claude so every Bash call runs without an
approval prompt. The Bash tool here means "go through SSH to the VM" —
the VM is physically isolated from the Mac, so the prompts add friction
without protection. **Read/Edit/Write keep prompting** because they hit
the Mac filesystem. Pass `--confirm-bash` to restore prompts for Bash
too (useful when the VM holds something you care about).

A walkthrough of the simplest case (single agent installs nginx and
verifies) is in [`examples/single-agent.md`](examples/single-agent.md).

## Multi-host (one agent, multiple VMs)

Give a single Claude session access to two or three VMs at once and let it
coordinate between them. Useful when you have, say, a web VM and a DB VM and
want one agent to set up the app on one and the schema on the other.

```bash
remote-launcher webvm --host dbvm                     # default=webvm, also dbvm
remote-launcher webvm --host dbvm --host cachevm      # three hosts
```

Inside Claude, route a Bash call by prefixing it with `@<host>`:

```
@webvm  systemctl status nginx
@dbvm   psql -c '\dt'
hostname                # no prefix → goes to the default host (webvm)
```

The launcher injects a multi-host block into the system prompt listing the
roster and rules. Each host has its own working directory, ControlMaster
socket, and shell-mode cache — `cd /tmp` on `webvm` does not affect `dbvm`.
Filesystems are independent: to move a file between hosts, the agent uses
`scp` (host-to-host) or pulls to the Mac and pushes back.

A worked example is in [`examples/multi-host.md`](examples/multi-host.md).

### Roadmap

- `--shared-workdir <path>` — auto-sync a Mac directory to all hosts so
  Read/Edit/Write on the Mac propagates to every VM.
- `@copy hostA:/path hostB:/path` helper for inter-host file transfer.
- ProxyJump / bastion examples.

## Multi-agent

Multiple Claude sessions, each in its own terminal, all targeting the
same VM (or the same set of VMs).

### Same VM, several agents

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

### Several agents over several VMs (3+)

Combine multi-host (one agent → many VMs) with multi-agent (many agents →
shared workspace) for larger coordinated runs. Each terminal opens its own
Claude session against the same set of hosts; agents share files via
filesystem on each VM (or via `scp` between VMs).

```bash
# All terminals see the same 3 VMs; default host is webvm.
TASK=~/projects/demo/MASTER.md

# Terminal 1 — coordinator (Agent 0)
remote-launcher webvm --host dbvm --host cachevm --task "$TASK"

# Terminals 2..4 — workers (Agents 1..3), one per VM responsibility
remote-launcher webvm --host dbvm --host cachevm --task "$TASK"   # Agent 1
remote-launcher webvm --host dbvm --host cachevm --task "$TASK"   # Agent 2
remote-launcher webvm --host dbvm --host cachevm --task "$TASK"   # Agent 3
```

Inside each Claude session, route by `@host` and stay in your assigned
role+host scope. Example role split in `MASTER.md`:

```
You are Agent N. Roles:
  Agent 0 — coordinator. Read /home/testuser/coord/state.json on @webvm; never edit other agents' files.
  Agent 1 — owns @webvm:/srv/app and nginx.
  Agent 2 — owns @dbvm:/var/lib/postgresql and migrations.
  Agent 3 — owns @cachevm:/etc/redis and cache config.
Write progress to /home/testuser/coord/agent-N.log on YOUR primary host.
```

Practical tips:

- Each terminal opens its own ControlMaster sockets (one per VM, per
  session) — at 4 agents × 3 VMs that's 12 sockets. SSH copes; just be
  aware if you cap MaxSessions/MaxStartups on the VM's sshd.
- Bash auto-approve is on by default per session — for cross-host
  destructive operations, consider `--confirm-bash` on the coordinator
  terminal only.
- Agents do NOT see each other's working directory. `cd` is per
  session × per host. Use absolute paths in shared coordination files.
- For 5+ agents, prefer scripting the launches in a tmux/wezterm layout
  rather than opening terminals by hand.

## Manual exploration with throwaway VMs

`tests/manual-multi-vm.sh` boots N (1–9) Ubuntu containers as distinct SSH
hosts and prints the exact `remote-launcher` command to run. Useful when
you want to play with multi-host without standing up real VMs.

```bash
tests/manual-multi-vm.sh        # 2 containers (mh-vm-1, mh-vm-2)
tests/manual-multi-vm.sh 3      # 3 containers
tests/manual-multi-vm.sh 5      # 5 containers
tests/manual-multi-vm.sh --down # tear down everything the script created
```

The script generates an SSH config under `tests/.manual-ssh-config`. To
have `remote-launcher` pick it up without modifying `~/.ssh/config`:

```bash
VM_SSH_OPTS="-F $(pwd)/tests/.manual-ssh-config" \
  remote-launcher mh-vm-1 --host mh-vm-2 --host mh-vm-3
```

(`VM_SSH_OPTS` flows through `ssh-shell` to every per-host SSH call.)

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
