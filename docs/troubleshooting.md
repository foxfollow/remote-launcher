# Troubleshooting

## "ssh-shell: cannot connect to <host>"

The wrapper failed at the bootstrap step. Check:
- `ssh -o BatchMode=yes <host> 'echo ok'` — does this work without prompting?
- `~/.ssh/config` — does the alias resolve correctly?
- `ssh -vvv <host>` — read the verbose output for the actual failure.

## Claude says "command not found" but the command exists on the VM

You're probably hitting one of two things:
1. `PATH` differs from your interactive ssh shell. Each remote-launcher bash call is a non-interactive shell — it sources `~/.bashrc` only if `BASH_ENV` is set. If your tooling lives in `/opt/<tool>/bin`, add it to `~/.profile` or use full paths.
2. The command is a function/alias defined in `~/.bashrc`. Non-interactive shells skip `.bashrc`. Use the actual binary.

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

## Multi-agent: agents see stale state from each other

This shouldn't happen — each `remote-launcher` invocation has a unique `VM_REMOTE_SESSION`. If it does:
- Verify by running `env | grep VM_REMOTE_SESSION` inside one Claude — it should be unique per terminal.
- Check `$TMPDIR/remote-launcher-*` — there should be one directory per running session.

## Dynamic Workflows: Bash calls fail or hang under heavy parallelism

**Symptom:** with many parallel subagents, some Bash commands time out or produce "Connection refused on control socket".

**Cause:** all subagents share one SSH ControlMaster connection. OpenSSH's default `MaxSessions=10` limits how many commands can run simultaneously over that connection. When more than 10 subagents invoke Bash at the same moment, the excess are queued — and if your SSH `ServerAliveInterval` fires before the queue drains, you get a timeout.

**Fix:** raise `MaxSessions` in the VM's `/etc/ssh/sshd_config`:

```
MaxSessions 50
```

Then `sudo systemctl reload sshd` (or equivalent). Tune the value to the maximum parallelism you expect from Dynamic Workflows.

## Dynamic Workflows: subagents land in the wrong directory

**Cause:** subagents inherit `CLAUDE_CODE_SHELL` and run on the VM, but they share the same per-session working-directory file. A `cd` in one subagent's call races with a `cd` in another.

**Fix:** write every subagent Bash call with an explicit absolute path:

```bash
cd /absolute/path && your-command
```

Never rely on a `cd` from a previous call persisting when subagents run concurrently.
