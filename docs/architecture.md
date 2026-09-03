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
2. `ssh-shell` resolves the target host from an optional `@host` prefix, then reads cwd from `$TMPDIR/remote-launcher-<session>/cwd-<host>` (creates if absent).
3. `ssh-shell` opens/reuses the ControlMaster socket at `~/.ssh/rl-<session>-<host>.s`.
4. It builds a shell program — `cd $CWD; $CMD; pwd > /tmp/.remote-launcher-cwd-<session>-<host>; exit $?` — **encodes** it, stages it into a temp file on the remote, and runs it with an explicit `/bin/sh` (see "Command transport" below).
5. After return, `ssh-shell` re-uses the same ControlMaster to `cat` the remote pwd file and updates the local cwd file.

## Command transport

The remote script is never handed to the far end as raw syntax. The login shell
there may be tcsh (OPNsense/FreeBSD) or anything else that would mangle `&&`,
redirections, or quoting, so the script travels encoded and is executed by an
explicitly named `/bin/sh`.

Two encodings, chosen per host:

| Encoding | Expansion | Remote requirement |
|---|---|---|
| base64 | 1.33x | a working decoder — `base64 -d`, `base64 --decode`, `base64 -D`, or `openssl base64 -d` |
| printf-octal (`\NNN` escapes) | 4x | `printf` only, a shell builtin in ash/dash/bash |

`printf-octal` is the universal floor. BusyBox firmware on consumer routers
(ASUSWRT, OpenWrt) is routinely built without the base64 applet, and base
FreeBSD ships no `base64(1)` either — on those hosts base64 is simply not an
option. The octal payload also contains nothing but backslashes and digits, so
it survives any login shell unquoted and holds no `%` for `printf` to read as a
conversion spec.

`ssh-shell` probes the host once per session (the probe itself rides the octal
encoding, since that always works) and caches the answer in
`$TMPDIR/remote-launcher-<session>/xfer-<host>`. An unreachable host is not
cached, so the next call probes again.

### Why stage into a file instead of piping

Earlier the script was piped straight into the remote shell:
`printf %s <b64> | base64 -d | /bin/sh`. When the decoder was missing, that
`/bin/sh` received empty stdin and exited **0** — the transport was dead while
the wrapper reported success on every call, with `base64: not found` surfacing
as the command's output. Decoding to a file and testing it before execution
turns that into a loud non-zero failure.

### Chunked staging

Linux caps a single argv entry at `MAX_ARG_STRLEN` (128 KiB) regardless of the
total `ARG_MAX`, so a long heredoc encoded into one ssh argument would fail with
"Argument list too long". Payloads over 60000 characters are appended to the
remote staging file in chunks across several ssh hops — cheap, because
ControlMaster keeps the connection open.

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
