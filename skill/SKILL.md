---
name: remote-launcher
description: Use when the user wants to operate a remote Linux host from Claude Code on the Mac while keeping Anthropic credentials only on the Mac. Triggers include deploying multi-container labs on a remote VM, running multi-agent setups (e.g., "you are Agent 1") against a remote host, executing builds/tests/sysadmin on a target machine via SSH, working with infrastructure where files must live on the VM. Activation typically means telling the user to launch via `remote-launcher <host>` instead of plain `claude`. Do NOT use for local-only work or tasks that don't involve a target host.
---

# remote-launcher skill

Operate a remote Linux host from Claude Code on the Mac, keeping Anthropic OAuth on the Mac.

## When applicable

User says things like:
- "Deploy this on the VM"
- "I have a sandbox at <host>, run X there"
- "Set up containers on <host>"
- "You are Agent N" (multi-agent scenario targeting a VM)
- "Use the lab VM" / "use my dev box"

## How to activate

Tell the user to launch via the launcher:

```
remote-launcher <ssh-host>
```

Or with their task pre-loaded:

```
remote-launcher <ssh-host> --task ~/path/to/PROMPT.md
```

The launcher sets `CLAUDE_CODE_SHELL` (Bash → VM) and appends a system-prompt block that explains the operating mode. The user then pastes their task / role assignment normally.

## Diagnostics

```
remote-launcher-doctor              # files / PATH check
remote-launcher-doctor <ssh-host>   # also live SSH + wrapper round-trip
```

## Architecture

- `bin/ssh-shell` — `CLAUDE_CODE_SHELL` wrapper. SSH ControlMaster, tracks cwd between calls.
- `bin/remote-launcher` — launcher: tests SSH, sets env, exec's claude with `--append-system-prompt`.
- `prompts/REMOTE_PROMPT.md` — instructs the model on Bash→VM and Read/Edit/Write→Mac discipline.
- `bin/remote-launcher-doctor` — sanity checks.

## Security model in one paragraph

Anthropic OAuth lives in macOS keychain. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` strips Anthropic env vars from the bash subprocess that invokes ssh. SSH itself does not forward env vars (no `SendEnv`) and we don't enable agent forwarding (no `-A`). Files originate from bash heredocs on the VM — they don't pass through the Mac filesystem.

For the full model: `docs/security-model.md`. To verify: `tests/run-tests.sh`.
