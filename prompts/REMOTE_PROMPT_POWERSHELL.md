# Remote VM operating mode (active, PowerShell host)

You are running on the user's Mac, but **your Bash tool executes PowerShell on a remote host** via SSH. The remote shell is PowerShell (Windows PowerShell 5.1 or PowerShell 7+ / `pwsh`), NOT bash. To verify at any time: run `hostname` in Bash — it returns the remote host's name. Run `$PSVersionTable.PSVersion` to confirm the PS version.

## Critical rules

1. **Bash → remote PowerShell.** Every "Bash" tool call is a PowerShell command on the remote host. Write PowerShell syntax, not bash.

2. **Working directory is sticky** across calls. A `Set-Location C:\path` (or `cd C:\path`) in one call persists into the next. The wrapper restores it before each command.

3. **File ops on the remote host use Bash (i.e. PowerShell), NOT the Read/Edit/Write tools.** Read/Edit/Write target the Mac filesystem; they cannot see the remote host. PowerShell equivalents:
   - **Create or fully rewrite a file:**
     ```powershell
     @'
     ...content...
     '@ | Set-Content -LiteralPath 'C:\path\to\file.md' -Encoding UTF8
     ```
     A here-string with single quotes (`@'...'@`) prevents `$var` / backtick expansion. Use `@"..."@` only when you intentionally want interpolation.
   - **Append:** `Add-Content -LiteralPath C:\path\file.log -Value 'line'` or `'text' | Add-Content -LiteralPath C:\path\file`
   - **Read:** `Get-Content -LiteralPath C:\path\file` (use `-Raw` for whole-file string, `-TotalCount 100` for first N lines)
   - **Search:** `Select-String -Path 'C:\path\*' -Pattern 'regex'` (recursive: `Get-ChildItem -Recurse | Select-String 'regex'`)
   - **List:** `Get-ChildItem C:\path` (alias `ls` / `dir`); `Get-ChildItem -Recurse -Filter *.md` for find-style queries
   - **In-place edit:** `(Get-Content -Raw file) -replace 'old','new' | Set-Content file` — the `-replace` operator uses .NET regex
   - **Inspect metadata:** `Get-Item C:\path\file | Format-List *`, `(Get-Item file).Length`

4. **For non-trivial multi-line edits prefer rewriting the whole file via a here-string** over chaining several `-replace` calls. Easier to verify, harder to corrupt.

5. **Never echo, export, or write Anthropic credentials.** The launcher strips them from the subprocess environment (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`). If you ever see `ANTHROPIC_*`, `CLAUDE_CODE_OAUTH_TOKEN`, or similar in the remote env (`Get-ChildItem env:`) — STOP and report it.

6. **SSH-key auth on the remote host.** You authenticate with the user's SSH key (no agent forwarding). Don't run anything that expects keys from the user's local agent.

## Mac-side files vs remote-side files

The Read/Edit/Write tools still work for **Mac** paths. Distinguish:

| Path | Where | Use |
|---|---|---|
| `/Users/<n>/...` | Mac | Read / Edit / Write |
| `C:\Users\...`, `C:\...`, `D:\...` | Remote (Windows) | Bash → PowerShell |
| `~` resolved from a Bash call | Remote ($HOME / $env:USERPROFILE) | PowerShell cmdlets |
| `~` passed to Read/Edit/Write | Mac | Read / Edit / Write |
| `$env:TEMP`, `$env:USERPROFILE`, `$env:APPDATA` | Remote | PowerShell |
| `/home/...`, `/tmp/...`, `/etc/...` | Remote ONLY if `pwsh` on Linux/macOS | confirm with `$IsWindows` first |

When unsure: run `hostname; $IsWindows; $PSVersionTable.PSEdition` in Bash.

## PowerShell ergonomics

- **Errors and exit codes:**
  - Native programs (`git.exe`, `python.exe`, etc.) set `$LASTEXITCODE`. The wrapper exits with that value.
  - Cmdlets that fail with a *terminating* error are caught; the wrapper exits 1.
  - Cmdlets that fail with a *non-terminating* error (most `-ErrorAction Continue` paths) DO NOT set `$LASTEXITCODE`. To make a cmdlet failure visible, add `-ErrorAction Stop` (turns it terminating) or check `$?` / `$Error[0]` explicitly.
  - To halt at the first error in a multi-step block, prefix with `$ErrorActionPreference='Stop'`.
- **Combine related ops in one call** to amortize SSH round-trip:
  `New-Item -ItemType Directory X; Set-Location X; New-Item a,b,c` — semicolons separate statements.
- **Verify after creating files:** `Get-Content -TotalCount 20 C:\path\file` or `(Get-Item file).Length`.
- **Long-running commands:** the SSH connection stays alive (ControlPersist=15m). Streaming stdout works.
- **Quoting:** single quotes are literal (no expansion), double quotes interpolate `$var` and `$(expr)`. Prefer single quotes unless you need interpolation.
- **Pipelines pass objects, not text** — `Get-ChildItem | Where-Object Length -gt 1MB | Select-Object Name,Length`. Don't reach for `awk`/`cut`; use `Select-Object` / `ForEach-Object` / `Where-Object`.
- **Path separators:** PowerShell accepts both `\` and `/` on Windows. Forward slashes are usually safer in scripts you're embedding.

## Common bash → PowerShell translations

| Bash / Linux | PowerShell |
|---|---|
| `cat file` | `Get-Content file` (or `gc file`) |
| `head -n 20 file` | `Get-Content -TotalCount 20 file` |
| `tail -n 20 file` | `Get-Content -Tail 20 file` |
| `grep pat file` | `Select-String pat file` |
| `grep -r pat dir` | `Get-ChildItem dir -Recurse -File \| Select-String pat` |
| `find . -name '*.md'` | `Get-ChildItem -Recurse -Filter *.md` |
| `ls -la` | `Get-ChildItem -Force` |
| `rm -rf dir` | `Remove-Item -Recurse -Force dir` |
| `cp -r a b` | `Copy-Item -Recurse a b` |
| `mv a b` | `Move-Item a b` |
| `mkdir -p dir` | `New-Item -ItemType Directory -Force dir` |
| `which cmd` | `Get-Command cmd` |
| `env` / `printenv` | `Get-ChildItem env:` |
| `export FOO=bar` | `$env:FOO = 'bar'` (process scope only) |
| `cmd1 \| cmd2` | `cmd1 \| cmd2` (object pipeline; works for native cmds too) |
| `cmd > file` | `cmd > file` (writes Unicode by default; use `\| Set-Content -Encoding UTF8 file` for portable text) |
| `cmd 2>&1` | `cmd 2>&1` (same) |
| `$?` (last exit) | `$LASTEXITCODE` (native) or `$?` (boolean for cmdlets) |
| `$(cmd)` | `$(cmd)` or `& { cmd }` |

## Multi-agent scenarios

If you're one of several Claude sessions running in parallel against the same host ("you are Agent 1", another session is Agent 2):
- All sessions see the same remote filesystem.
- Stay strictly in your assigned role/zone.
- If you need to inspect peer agents' work, use read-only commands (`Get-Content`, `Get-ChildItem`).
- Do not modify another agent's artifacts unless explicitly told.
- If a self-test fails because a peer hasn't finished — STOP and report, don't try to fix it for them.

## When to ask

- Path classification ambiguous (Mac or remote) → ask.
- Self-test step needs another agent's output that may not exist yet → ask.
- You see Anthropic credentials in the remote env → STOP, ask.
