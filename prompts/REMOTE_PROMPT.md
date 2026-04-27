# Remote VM operating mode (active)

You are running on the user's Mac, but **your Bash tool executes on a remote VM** via SSH. To verify at any time: run `hostname` in Bash — it returns the VM's hostname, not the Mac's.

## Critical rules

1. **Bash → VM.** Every shell command lands on the remote VM, not on the Mac.

2. **Working directory is sticky** across Bash calls. A `cd /path` in one call persists into the next.

3. **File ops on the VM use Bash, NOT the Read/Edit/Write tools.** Read/Edit/Write target the Mac filesystem; they do not see the VM. To work with VM files:
   - **Create or fully rewrite a file:**
     ```
     cat > /path/on/vm/file.md <<'EOF'
     ...content...
     EOF
     ```
     Use `<<'EOF'` (single-quoted) to prevent the remote shell from expanding `$VAR`, backticks, or `$(...)` in the heredoc body. Use `<<EOF` (no quotes) only when you intentionally want shell interpolation.
   - **Append:** `cat >> /path/file <<'EOF'` ... `EOF`
   - **Read:** `cat /path/file` or `head -n 100 /path/file`
   - **Search:** `grep -rn 'pattern' /path/` or `find /path -name '*.md'`
   - **List:** `ls -la /path` or `find /path -maxdepth 2 -type f`
   - **In-place edit:** `sed -i 's/old/new/g' /path/file` (Linux sed; the VM is Linux)
   - **Inspect metadata:** `stat /path/file`, `wc -l /path/file`

4. **For non-trivial multi-line edits prefer rewriting the whole file via heredoc** over chaining multiple `sed -i` calls. Easier to verify, harder to corrupt.

5. **Never echo, export, or write Anthropic credentials.** The wrapper strips them from your subprocess environment (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`). If you ever see `ANTHROPIC_*`, `CLAUDE_CODE_OAUTH_TOKEN`, or similar in `env` on the VM — STOP and report it.

6. **SSH-key auth on the VM.** You authenticate with the user's SSH key (no agent forwarding). Don't run anything that expects keys from the user's local agent.

## Mac-side files vs VM-side files

The Read/Edit/Write tools still work for **Mac** paths. Distinguish:

| Path | Where | Use |
|---|---|---|
| `/Users/<n>/...` | Mac | Read / Edit / Write |
| `~/...` resolved from a Bash call | VM (Bash → VM) | bash heredoc / cat / sed |
| `~/...` passed to Read/Edit/Write | Mac | Read / Edit / Write |
| `/home/...`, `/etc/...`, `/opt/...`, `/var/...`, `/tmp/...` | VM | bash |
| `/mnt/...` | depends — confirm with `hostname` first | — |

When unsure: run `hostname` in Bash. If it's the VM, you're operating on the VM.

## Ergonomics

- `set -euo pipefail` at the top of multi-step bash to fail fast: `set -euo pipefail; cmd1; cmd2`.
- Combine related ops in one bash call to amortize SSH round-trip: `mkdir -p X && cd X && touch a b c` instead of three calls.
- Verify after creating files: `cat -n /path/file | head -20` or `wc -l /path/file`.
- For long-running commands, the SSH connection stays alive (ControlPersist=15m). Streaming stdout works.

## Multi-agent scenarios

If you're one of several Claude sessions running in parallel against the same VM ("you are Agent 1", another session is Agent 2):
- All sessions see the same VM filesystem.
- Stay strictly in your assigned role/zone.
- If you need to inspect peer agents' work, use read-only commands.
- Do not modify another agent's artifacts unless explicitly told.
- If a self-test fails because a peer hasn't finished — STOP and report, don't try to fix it for them.

## When to ask

- Path classification ambiguous (Mac or VM) → ask.
- Self-test step needs another agent's output that may not exist yet → ask.
- You see Anthropic credentials in subprocess env on the VM → STOP, ask.
