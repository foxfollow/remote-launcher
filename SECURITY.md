# Security policy

## Threat model

`remote-launcher` is a thin layer between Claude Code on a Mac and a remote Linux host. It assumes:

- The Mac is trusted (your machine; OAuth token sits in macOS keychain).
- The remote host is potentially shared but reached via SSH key auth you control.
- The network between them is untrusted (mitigated by SSH).

Out of scope:
- Compromise of the Mac itself (e.g., an attacker who already has shell on your Mac can read your keychain and SSH keys).
- Compromise of the SSH server-side (e.g., other root users on the VM reading your SSH session memory).
- Resource starvation by other VM users.

## What we protect

| Asset | Protection |
|---|---|
| Anthropic OAuth token | Stays in macOS keychain. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` removes Anthropic env vars from subprocess (bash) environment, so SSH never has them to forward. |
| SSH private key on the Mac | Used only for Mac→VM. Agent forwarding (`-A`) is intentionally OFF — keys are not exposed on the VM. |
| Session ControlMaster socket | Lives in your `$TMPDIR` (per-user). |
| File contents written during a session | Originate from bash heredocs *on the VM* — never round-trip through Mac filesystem. |

## How we verify

The `tests/` directory exercises every above protection:
- `04-env-scrub.sh` — sets fake `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` on Mac, verifies they do NOT appear in `env` on the VM.
- `05-no-agent-forwarding.sh` — verifies `SSH_AUTH_SOCK` is not set on the VM.

Run `./tests/run-tests.sh` after any change to wrapper code.

## Reporting a vulnerability

If you find a security issue, please report it via one of:

- **GitHub private security advisory** (preferred): use the *Security* tab → *Report a vulnerability* on this repo.
- **Email**: [d3f0ld@pm.me](mailto:d3f0ld@pm.me?subject=remote-launcher%20security).

**Do not** include credential samples or sensitive logs in public issues.

## Known limitations

- We rely on OpenSSH defaults for env-var handling. If a future OpenSSH version changes how `SendEnv`/`AcceptEnv` work, re-verify.
- We rely on Claude Code's `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` semantics. If Anthropic changes the semantics or the env-var name, re-verify.
- Test harness uses `apple/container` 0.x — pre-1.0 software. Behavior may shift between versions.
