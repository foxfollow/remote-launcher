# Architecture

## Process model

```
┌─ Mac ────────────────────────────────────┐    ┌─ Remote VM ──┐
│                                          │    │              │
│  user terminal                           │    │              │
│   │                                      │    │              │
│   └─► remote-launcher <host>             │    │              │
│        │ sets env                        │    │              │
│        │  CLAUDE_CODE_SHELL=ssh-shell    │    │              │
│        │  CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1   │              │
│        │  VM_REMOTE_HOST=<host>          │    │              │
│        │  VM_REMOTE_SESSION=<id>         │    │              │
│        │                                 │    │              │
│        └─► claude (Claude Code CLI)      │    │              │
│             │  reads OAuth from keychain │    │              │
│             │                            │    │              │
│             ├── Read/Edit/Write tools ──►│  Mac files        │
│             │                            │    │              │
│             └── Bash tool ───────────────┼────┼─ssh-shell ──►│ ssh ──► /bin/sh -c '...'
│                  │ -c '<command>'        │    │              │
│                                          │    │              │
└──────────────────────────────────────────┘    └──────────────┘
```

## Files involved per Bash call

1. Claude calls `<CLAUDE_CODE_SHELL> -c "<cmd>"` — `<CLAUDE_CODE_SHELL>` is `bin/ssh-shell`.
2. `ssh-shell` reads cwd from `$TMPDIR/remote-launcher-<session>/cwd` (creates if absent).
3. `ssh-shell` opens/reuses ControlMaster socket at `$TMPDIR/remote-launcher-<session>/ssh.sock`.
4. SSH forwards a multi-line shell program: `cd $CWD; $CMD; echo $? > /tmp/__exitcode; pwd > /tmp/__pwd; exit ...`.
5. After return, `ssh-shell` re-uses the same ControlMaster to `cat /tmp/__pwd` and updates local cwd file.

## Why no subshell around $CMD

Earlier drafts wrapped `$CMD` in a subshell `( $CMD )`. This breaks `cd` persistence: `cd /tmp` inside a subshell doesn't change the outer shell's cwd, so the subsequent `pwd > $REMOTE_PWD_FILE` captures the OLD cwd. Without the subshell, `cd` mutates the actual remote shell's cwd, and `pwd` captures it correctly. The trade-off: a `set -e` or `exit` in `$CMD` affects the wrapper's exit code logic. Acceptable — the alternative breaks the primary use case.

## Why no Mutagen / file sync

Considered and rejected. Mutagen adds a daemon, hidden state, and possible silent desyncs. For our workflow, files belong on the VM (where they're built and consumed). To pull artifacts: `scp -r myvm:path ~/local`.

## Why state per session, not per host

Each `remote-launcher` invocation generates a unique `VM_REMOTE_SESSION`. State (cwd, ControlMaster socket) is namespaced by session. So:
- Two parallel `remote-launcher` against same host → independent cwds, independent SSH sockets.
- Sessions don't leak state to each other.
- ControlPersist at 15 min cleans up automatically.

Trade-off: 4 parallel sessions = 4 SSH connections to the VM (instead of 1 shared). VMs handle this comfortably.
