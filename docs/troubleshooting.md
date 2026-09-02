# Troubleshooting

## "ssh-shell: cannot connect to <host>"

The wrapper failed at the bootstrap step. Check:
- `ssh -o BatchMode=yes <host> 'echo ok'` — does this work without prompting?
- `~/.ssh/config` — does the alias resolve correctly?
- `ssh -vvv <host>` — read the verbose output for the actual failure.

## "Permission denied (publickey)" at launch

The preflight probe runs with `BatchMode=yes`, so it fails instead of hanging on
a prompt. Since 0.2.4 the launcher recovers instead of bailing: if the error
looks like an auth failure it will, in order,

1. offer to `ssh-add` the key `ssh -G <host>` says it would use (one passphrase
   prompt; every later connection — including the wrapper's, which stay
   `BatchMode=yes` — then works via the agent), and
2. retry the connection with prompting enabled, opening the ControlMaster socket
   `ssh-shell` reuses (`~/.ssh/rl-<session>-<host>.s`, `ControlPersist=8h`), so a
   password typed once covers the whole session.

If both fail it's a real authorization problem, not a locked key — check
`ssh -vvv <host>` and the host's `authorized_keys`.

Notes:
- Recovery needs a terminal. Under `cron`/CI (no `/dev/tty`) the launcher says so
  and exits — load the key into an agent beforehand.
- Route 2 depends on the master connection staying alive. Loading the key into
  the agent (route 1, or `ssh-add` before launching) is the sturdier fix.
- Unreachable hosts and DNS failures are *not* retried interactively — you'd wait
  out a timeout to be asked for a password that was never the problem.

## Every Bash call returns `base64: not found` (BusyBox routers, FreeBSD)

**Symptom:** every single Bash call comes back with the same line —

```
/bin/sh: base64: not found
```

— and nothing else. Commands appear to "succeed" (exit 0), the launcher started
cleanly, and `ssh <host> 'echo hi'` from your terminal works fine.

**Cause:** the POSIX transport encodes each command and decodes it on the far
end. Before 0.2.5 it assumed `base64 -d` existed there. BusyBox firmware on
consumer routers (ASUSWRT, OpenWrt) is commonly built without the base64
applet, and base FreeBSD has no `base64(1)` either. The decoder was missing, so
the shell at the end of the pipe got empty stdin and exited 0 — which is why the
failure looked like a successful command with strange output rather than an
error.

**Fix:** upgrade to 0.2.5 or later. `ssh-shell` now probes the host once per
session and falls back to a `printf`-octal encoding that needs only a shell
builtin. Nothing to configure.

Confirm which transport a host gets:

```
remote-launcher-doctor <host>
```

It reports either `remote base64 usable — base64 command transport` or
`no usable remote base64 — falling back to printf-octal transport`.

**Note for embedded targets:** the octal encoding puts ~3x more bytes on the
wire than base64 (4 characters per byte instead of 1.33). Irrelevant for
ordinary commands; if you routinely write large files over a slow link to a
BusyBox host, installing coreutils there (`opkg install coreutils-base64` on
OpenWrt, an Entware package on ASUSWRT) restores the base64 path.

## Claude says "command not found" but the command exists on the VM

You're probably hitting one of two things:
1. `PATH` differs from your interactive ssh shell. Each remote-launcher bash call is a non-interactive shell — it sources `~/.bashrc` only if `BASH_ENV` is set. If your tooling lives in `/opt/<tool>/bin`, add it to `~/.profile` or use full paths.
2. The command is a function/alias defined in `~/.bashrc`. Non-interactive shells skip `.bashrc`. Use the actual binary.

## `@host` prefix ignored — `eval: @localhost: not found`

Symptom: in a multi-host session, `@localhost hostname` (or any `@host …`) fails with

```
/bin/sh: 1: eval: @localhost: not found
```

and the error comes from the **default** host, not the one you addressed. The prefix was never recognised, so the whole command went to the default host verbatim.

Cause: Claude Code's Bash tool wraps every command in a bash prelude ending in `eval '<your command>'`, and that prelude changes between releases (2.1.173 added snapshot sourcing, 2.1.258 added a `{ \builtin unalias … }` block). Older `ssh-shell` versions matched the prelude as one exact string, so a new release silently broke routing. Since 0.2.5 `ssh-shell` anchors on the stable `shopt -u extglob` token and takes the first `eval '` after it, so extra prelude is tolerated.

If you still see this, check which wrapper is actually running — `rl-set-team`/`remote-launcher` on `PATH` may be an older Homebrew install rather than your checkout:

```
which remote-launcher        # ~/.local/bin/… (install.sh) or /opt/homebrew/bin/… (brew)
remote-launcher --version
```

Then upgrade (`brew upgrade remote-launcher`) or run `./install.sh` from the checkout, which puts `~/.local/bin` symlinks ahead of Homebrew. Regression test: `bash tests/cases/08-wrapped-localhost-routing.sh` (no VM needed).

## `cd` in one Bash call doesn't persist to the next

Run `remote-launcher-doctor <host>` and check the cwd persistence test. If it fails:
- The wrapper might be using a stale subshell version. Make sure `bin/ssh-shell` matches the version in this repo (no `( $CMD )` subshell wrapping).
- The remote pwd file `/tmp/.remote-launcher-cwd-<session>` may be unwriteable. Try a different `$TMPDIR`.

## Bash commands run on the Mac instead of the VM

Symptom: inside Claude, `hostname` returns your Mac's name, `whoami` returns your Mac user. The launcher started without errors but Bash never crossed SSH.

Cause: Claude Code only honors `CLAUDE_CODE_SHELL` if the path string contains the substring `bash` or `zsh`. A path like `bin/ssh-shell` is silently rejected and Bash falls back to `/bin/bash`. We work around this with the `bin/ssh-shell-bash` symlink — `remote-launcher` points `CLAUDE_CODE_SHELL` at the symlink so the path passes the check.

If `bin/ssh-shell-bash` is missing (e.g., the symlink wasn't preserved during a copy), recreate it:

```
cd <repo>/bin && ln -s ssh-shell ssh-shell-bash
```

`remote-launcher-doctor` checks for this symlink.

## "claude" hangs or crashes during startup

- `CLAUDE_CODE_SHELL` requires Claude Code 2.0.65+. Update: `npm install -g @anthropic-ai/claude-code@latest`.
- Try without the prompt: `remote-launcher <host> --no-prompt` to isolate whether the issue is the system-prompt addendum or the wrapper.

## SSH ControlMaster errors

If you see "Control socket connect: No such file or directory" repeated:
- The ControlPersist period (15min) expired between calls.
- The next call should re-establish. If it doesn't, manually clean: `rm -rf $TMPDIR/remote-launcher-*` and retry.

## Tests fail at "container run"

- Apple `container` requires macOS 26 and Apple Silicon.
- `container system start` must be running. Check: `container system status`.
- For older macOS: skip tests, the launcher still works against your real VM.

## Tests fail at SSH-wait

- Container is up but sshd inside isn't ready. `tests/run-tests.sh` waits up to 30 seconds. If your machine is slow or the test image is rebuilding, increase the timeout in `run-tests.sh`.

## `git reset --hard` (or similar destructive git commands) refused by Claude

Starting with Claude Code 2.1.183, commands that irrecoverably destroy work are blocked in
auto-approve mode: `git reset --hard`, `git checkout -- .`, `git clean -fd`,
`git stash drop`, `git commit --amend` (when the commit was not made by Claude
this session), and infra-destroy commands (`terraform destroy`, `pulumi destroy`,
`cdk destroy`).

Because remote-launcher passes `--allowedTools 'Bash(*)'` by default, the agent
runs in auto-approve mode and these restrictions apply — even though the commands
would run on a remote VM.

**Workarounds:**

- **Ask Claude explicitly.** The block is lifted when the user's current message
  specifically requests the destructive action ("please run `git reset --hard HEAD~1`").
- **Run it yourself.** SSH directly to the VM and run the command manually.
- **Use `--confirm-bash`** (`remote-launcher myvm --confirm-bash`). With Bash
  prompts on, auto-approve mode is not engaged and the restriction does not apply.

## Unattended session stops retrying after too many API errors

Starting with Claude Code 2.1.186, `CLAUDE_CODE_MAX_RETRIES` is capped at 15.
If you were relying on a higher value to keep a long-running remote session alive
through API blips, use `CLAUDE_CODE_RETRY_WATCHDOG` instead — it is designed
for unattended sessions and is not capped the same way.

Add it to the `remote-launcher` invocation or your shell environment:

```bash
export CLAUDE_CODE_RETRY_WATCHDOG=1
remote-launcher myvm
```

**Note (2.1.196+):** the streaming idle watchdog is now on by default for all
providers — when the **API response stream** produces no events for 5 minutes,
the request is aborted and retried automatically. This watches the model's
response stream, not your Bash commands: a long-running silent command on the
VM does not trip it. Set `CLAUDE_ENABLE_STREAM_WATCHDOG=0` to disable.

**Note (2.1.198+):** brief network drops that interrupt a response mid-stream
(ECONNRESET and similar transient errors) now retry automatically with backoff
instead of aborting the turn. This covers the common case of a momentary WiFi
blip while a long assistant response is streaming — no workaround needed.

## Background agent over SSH fails with "Could not switch to audit session"

On macOS, launching a background agent (`claude --bg`) from an SSH session
could fail to cold-start with "Could not switch to audit session". Fixed in
Claude Code **2.1.199** — upgrade:

```bash
npm install -g @anthropic-ai/claude-code@latest
```

Note this affects `claude --bg` started over SSH *into a Mac* — not
remote-launcher's normal mode, where Claude runs locally on the Mac and only
Bash crosses SSH to the VM.

## Unattended session stalls on an `AskUserQuestion` dialog

Starting with Claude Code **2.1.200**, `AskUserQuestion` dialogs no longer
auto-continue by default — they block until answered. In an unattended
remote/SSH session where nobody is watching the terminal, a clarifying
question (rare, but possible on ambiguous tasks) can stall the run.

**Mitigations:**

- **Opt into an idle timeout via `/config`** — the dialog then auto-continues
  after the configured idle period. This is the official knob for unattended
  sessions.
- Front-load all required decisions in the initial task description so Claude
  doesn't need to ask.
- For long-running unattended tasks, keep a `tmux` pane attached so you can
  spot and answer any dialog that appears.

## Unattended session fails mid-run with 401 errors

**Symptom:** a long-running or headless (`-p`) session authenticated with
`CLAUDE_CODE_OAUTH_TOKEN` starts returning 401s partway through, and only
recovers after a restart.

**Cause:** with a stored interactive login present *as well as* the token, the
login's short-lived token could transiently replace the long-lived
`CLAUDE_CODE_OAUTH_TOKEN`. Fixed in Claude Code **2.1.225** — upgrade:

```bash
npm install -g @anthropic-ai/claude-code@latest
```

**Until you can upgrade,** keep just one credential on the Mac: either
`claude auth logout` and rely on the token, or unset the token and rely on the
stored login. `claude auth status` shows which one a session picked up.

Note this is a Mac-side credential problem, not an SSH one — the launcher
`exec`s `claude` on the Mac with your environment, and
`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` keeps `CLAUDE_CODE_OAUTH_TOKEN` out of the
Bash subprocess that crosses SSH, so the VM never sees the token either way.

## Dynamic Workflows: Bash calls fail under heavy parallelism

**Symptom:** with many parallel subagents, some Bash calls fail with SSH mux
errors ("mux_client_request_session: session request failed", "Connection
refused on control socket") or time out.

**Cause:** all subagents in one session share one SSH ControlMaster connection
per host. OpenSSH's server-side default `MaxSessions 10` caps how many
multiplexed sessions can be open on that connection at once; sessions beyond
the cap are refused. Each Bash call also briefly opens a second session to
read back the working directory, so the ceiling is reached sooner than "10
parallel commands".

**Fix:** raise `MaxSessions` in the VM's `/etc/ssh/sshd_config`:

```
MaxSessions 50
```

Then `sudo systemctl reload sshd` (or your init system's equivalent). Tune the
value to the maximum parallelism you expect.

## Dynamic Workflows: subagents land in the wrong directory

**Cause:** subagents inherit `CLAUDE_CODE_SHELL` and the `VM_REMOTE_*` env
vars, so their Bash calls route to the VM — but they share the session's
per-host working-directory file (`$TMPDIR/remote-launcher-<session>/cwd-<host>`).
Every call starts from that file's cwd and writes its own cwd back on exit, so
concurrent `cd` calls race each other.

**Fix:** in subagent Bash calls, don't rely on the sticky cwd — use absolute
paths everywhere, or open each call with an explicit `cd /absolute/path && …`.
Never rely on a `cd` from a previous call persisting when subagents run
concurrently.

## Multi-agent: agents see stale state from each other

This shouldn't happen — each `remote-launcher` invocation has a unique `VM_REMOTE_SESSION`. If it does:
- Verify by running `env | grep VM_REMOTE_SESSION` inside one Claude — it should be unique per terminal.
- Check `$TMPDIR/remote-launcher-*` — there should be one directory per running session.
