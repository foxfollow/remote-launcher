# Changelog

All notable changes to remote-launcher will be documented here.

## [Unreleased]

### Fixed
- Remote hosts without `base64` are supported again — previously **every** Bash call failed on them. The POSIX transport hard-required a `base64 -d` decoder on the far end, which BusyBox firmware on consumer routers (ASUSWRT, OpenWrt) and base FreeBSD do not ship. `ssh-shell` now probes the host once per session (`base64 -d`, `base64 --decode`, `base64 -D`, `openssl base64 -d`) and falls back to a `printf`-octal encoding that needs only a shell builtin. The result is cached per host in `$TMPDIR/remote-launcher-<session>/xfer-<host>`; an unreachable host is not cached.
- A dead transport no longer reports success. The script used to be piped straight into the remote `/bin/sh`, so a missing decoder left that shell with empty stdin and it exited **0** — the wrapper returned exit 0 on every call while `base64: not found` came back as the command's output. The script is now decoded into a temp file and checked before execution, so a staging failure exits non-zero with a named error.
- Long commands no longer risk "Argument list too long". Linux caps one argv entry at `MAX_ARG_STRLEN` (128 KiB) whatever `ARG_MAX` is, so a large heredoc could exceed it in a single ssh argument. Payloads over 60000 characters are now staged to the remote in chunks over the existing ControlMaster connection.
- `remote-launcher-doctor <host>` reports which command transport a host gets (base64 or printf-octal), and points at the wrapper debug log when the round-trip check fails.
- New test case `tests/cases/09-transport-fallback.sh` covering both encodings, exit-code propagation, quoting transparency, cwd persistence, and chunked staging. It uses a fake `ssh` on `PATH`, so it needs no VM and runs standalone.

### Docs
- Architecture: documented the command transport (encodings, per-host probe, why the script is staged to a file instead of piped, chunked staging). The step-by-step "files involved per Bash call" list was stale — it described a raw multi-line program with no encoding at all, and named pre-multi-host state paths.
- Troubleshooting: new section for the `base64: not found` symptom, ahead of the "command not found" section that would otherwise mislead.
- README limitations + REMOTE_PROMPT: state that the remote needs little beyond a POSIX `/bin/sh`, and that the prompt's GNU-flavored tool advice (`sed -i`, `grep -rn`) needs adapting on BusyBox/BSD hosts.
- Troubleshooting: an unattended or headless (`-p`) session authenticated with `CLAUDE_CODE_OAUTH_TOKEN` could start returning 401s mid-run when a stored interactive login was also present — fixed in Claude Code 2.1.225; until then, keep only one credential on the Mac. The token never reaches the VM either way (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`).

### Tracking
- Bumped Claude Code tracked version to 2.1.227. Reviewed 2.1.222–2.1.227 for project relevance; no code changes warranted.

## [0.2.4]

### Fixed
- `remote-launcher <host>` no longer gives up with `ERROR: cannot SSH to <host>` when the key needs a passphrase or the host wants a password. The preflight still probes with `BatchMode=yes` (fast, never hangs), but on an auth error it now offers to `ssh-add` the key `ssh -G` reports for that host, then falls back to an interactive connection that opens the same ControlMaster socket `ssh-shell` reuses (`ControlPersist=8h`) — so one prompt covers the session. Unreachable hosts and DNS failures are not retried interactively, and with no `/dev/tty` (cron/CI) the launcher reports that and exits as before.

### Docs
- Troubleshooting: streaming idle watchdog (on by default since Claude Code 2.1.196) aborts and **retries** a stalled API response stream — it does not affect silent Bash commands; transient mid-stream network drops auto-retry since 2.1.198.
- Troubleshooting: `AskUserQuestion` dialogs no longer auto-continue by default (Claude Code 2.1.200) — opt into an idle timeout via `/config` for unattended sessions.
- Troubleshooting: background agents (`claude --bg`) over SSH into a Mac failed with "Could not switch to audit session" — fixed in Claude Code 2.1.199.
- Troubleshooting + REMOTE_PROMPT: Dynamic Workflows — parallel subagents share one ControlMaster connection per host (raise `MaxSessions` on the VM) and one sticky-cwd file (use absolute paths in subagent Bash calls).

### Tracking
- Bumped Claude Code tracked version to 2.1.202.

## [0.2.3]

### Added
- `remote-launcher -v` / `--version` (and `remote-launcher-doctor -v`) print the version and, best-effort, whether a newer GitHub release exists. Previously `-v` was treated as a host name (`testing SSH to -v`). Version is read from a new top-level `VERSION` file — a single source of truth shared by both scripts (the Homebrew formula writes it from the formula version).
- Homebrew distribution: `brew install foxfollow/stone/remote-launcher`. Tagged releases auto-bump the formula via `.github/workflows/release.yml` (creates a GitHub Release and updates `foxfollow/homebrew-stone`).

### Changed
- `remote-launcher-doctor` now passes its install check when `remote-launcher` is reachable on `PATH` via Homebrew (`/opt/homebrew/bin`), not only via `~/.local/bin`. It also prints the version in its header.

## [0.2.2]

### Fixed
- `@host` prefix routing was silently ignored under Claude Code 2.1.173+. The Bash tool now prepends a prelude (shell-snapshot `source` + `CLAUDE_CODE_VERSION` export) before the `eval '<inner>'` marker, so `ssh-shell`'s parser — which anchored on the command *starting* with `shopt … && eval '` — skipped @host detection entirely and passed `@localhost`/`@vm` to the shell verbatim (`@localhost: not found`). The parser now locates the `eval` marker anywhere in the command, preserving the prelude. Both the POSIX and PowerShell wrapper-stripping paths are fixed.
- `remote-launcher`: unknown flags meant for `claude` now forward correctly even when they take a bare-word value. Previously `remote-launcher vm localhost --resume <id>` mis-parsed `<id>` as a host and tried to SSH into it. An unknown flag now forwards itself and everything after it to `claude` (implicit `--`); put host names before any `claude` flags.
- New test case `tests/cases/08-wrapped-localhost-routing.sh` exercising @host routing against the real wrapped command format via the no-VM `localhost` path (prefix stripping, embedded quotes, unknown-host error).

## [0.2.1]

### Added
- `localhost` as a special host that runs Bash on the Mac directly (no SSH, no ControlMaster). Mix it into a multi-host session: `remote-launcher remote-vm1 localhost remote-vm2`. `@localhost` commands execute via local `/bin/sh` with per-host cwd persistence, exit-code passthrough, and the same routing/state-file infrastructure as remote hosts. Useful for letting the agent run local Mac commands (git, file moves) without restarting Claude outside the launcher.
- Bare positional hosts on the command line: `remote-launcher vm1 vm2 vm3` is now equivalent to `remote-launcher vm1 --host vm2 --host vm3`. Unknown `-*` flags still forward to Claude.
- README section "Including the Mac itself (`localhost`)" plus a security note: under default Bash auto-approve, `@localhost` commands run unattended — pair with `--confirm-bash` if that's a concern.

### Tracking
- Bumped Claude Code tracked version to 2.1.159.

## [0.2.0]

### Added
- Multi-host mode. Pass extra hosts via repeatable `--host <ssh-host>` flags (`remote-launcher webvm --host dbvm --host cachevm`). Inside Claude, route a Bash call to a specific host with the `@<host>` prefix as the first token (e.g. `@dbvm psql -c '\dt'`). Without a prefix, the command goes to the default (first) host. Each host gets its own ControlMaster socket, working directory, and shell-mode cache — sessions are isolated. The launcher injects a multi-host roster into the system prompt at runtime.
- New env vars exported by the launcher: `VM_REMOTE_HOSTS`, `VM_REMOTE_DEFAULT_HOST`, `VM_REMOTE_SHELLS`, `VM_REMOTE_PS_EXES`. Single-host invocations continue to work unchanged (`VM_REMOTE_HOST` / `VM_REMOTE_SHELL` still point at the default host).
- New example `examples/multi-host.md`.
- New test case `tests/cases/07-multi-host-routing.sh` covering @host routing, per-host cwd isolation, per-host ControlMaster sockets, the unknown-host error path, and env scrubbing under multi-host.

## [0.1.0]

### Added
- Initial release.
- `bin/remote-launcher --confirm-bash` flag. By default the launcher passes `--allowedTools 'Bash(*)'` so Bash calls (= remote VM) auto-approve; Read/Edit/Write (= Mac) still prompt. `--confirm-bash` restores prompts for Bash too.
- `bin/ssh-shell` — `CLAUDE_CODE_SHELL` wrapper, forwards Bash to remote via SSH ControlMaster, tracks remote cwd between calls.
- `bin/remote-launcher` — launcher CLI: tests SSH, sets env, exec's Claude with system-prompt addendum.
- `bin/remote-launcher-doctor` — diagnostic.
- `prompts/REMOTE_PROMPT.md` — appended to Claude system prompt; explains Bash→VM, Read/Edit/Write→Mac, heredoc for VM files.
- `skill/SKILL.md` — Claude Code skill manifest.
- Test harness using Apple's `container` (`tests/`).
- `install.sh` / `uninstall.sh`.
- Documentation: architecture, security model, troubleshooting.
