# Changelog

All notable changes to remote-launcher will be documented here.

## [Unreleased]

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
