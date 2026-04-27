# Security model

## Asset map

| Asset | Where it lives | Who can read it |
|---|---|---|
| Claude OAuth token | macOS keychain (`Login` keychain, this user's account) | Only processes started by this user that pass keychain ACL |
| `claude` process memory | Mac userspace | This user; root |
| Mac SSH private key | `~/.ssh/id_*` (file mode 600) | This user; root |
| `ssh-shell` state (cwd file, ControlMaster socket) | `$TMPDIR/remote-launcher-<session>/` | This user only (`$TMPDIR` is per-user on macOS) |
| Files created during a Claude session | Remote VM filesystem | Whoever has access on the VM |

## Threats and mitigations

### T1 — OAuth token reaches the VM

**How it might happen:** Claude Code subprocess exports `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, etc.; subprocess is `bash`; bash invokes `ssh`; ssh forwards env to remote.

**Mitigations:**
1. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` — Claude Code strips Anthropic env vars before subprocess launches.
2. OpenSSH does not forward env vars unless `SendEnv` is set client-side AND `AcceptEnv` is set server-side. We don't set `SendEnv`. So even pre-scrub, the variables would not cross.
3. The local subprocess shell is `ssh-shell`, not `claude`. By the time it's invoked, env is already scrubbed.

**Verification:** `tests/cases/04-env-scrub.sh` sets fake `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` in the launcher's env, then runs `env` on the VM via the wrapper, and asserts none of those variables (or their values) appear.

### T2 — SSH key reaches the VM

**How it might happen:** Agent forwarding (`-A`) is enabled, so the user's local ssh-agent is exposed on the VM and another user can hijack it.

**Mitigation:** We never use `-A`. The Mac SSH key authenticates the Mac→VM connection only; no chaining.

**Verification:** `tests/cases/05-no-agent-forwarding.sh` checks `$SSH_AUTH_SOCK` is unset on the VM.

### T3 — File written to disk on VM contains creds

**How it might happen:** A bash command on the VM writes a credential file (e.g., `aws configure`, `gh auth login`); that file persists on the VM.

**Mitigation:** Out of scope at the wrapper level — same as any SSH workflow. We document this in README. Don't run "log me in to X" commands on a shared VM unless you trust other users on it.

### T4 — Local ControlMaster socket hijack

**How it might happen:** Another user on the Mac reads `$TMPDIR/remote-launcher-*/ssh.sock` and uses it to send commands as you on the VM.

**Mitigation:** macOS sets per-user `$TMPDIR` (`/var/folders/.../T/`) with 0700 permissions. Other non-root users cannot read it. Root on your Mac can — but root on your Mac can also read your keychain, so this is not a practical escalation.

### T5 — Compromised Mac

**Out of scope.** If an attacker has shell on your Mac, they have your SSH key, your OAuth token, your data. `remote-launcher` does not protect against host compromise.

### T6 — Compromised VM (other root users)

**Partially in scope.** Other root users on the VM can read your shell's memory, your stdout, your bash_history. They cannot:
- Steal your OAuth token (it never reaches the VM).
- Use your SSH key to reach other hosts (no agent forwarding).

But they CAN see what you ran, see file contents you opened, etc. Use a dedicated VM for sensitive work.

## What we don't claim

- We don't claim "no secrets ever land on the VM." If you `cat ~/Documents/secret.txt` on the Mac and pipe it into a bash command, that's on you.
- We don't claim wire encryption beyond what SSH provides.
- We don't claim resistance to active tampering with `bin/ssh-shell` itself. If an attacker can edit the wrapper, they can do anything. Keep the project on a trusted disk; consider running `git diff` if you're paranoid.
