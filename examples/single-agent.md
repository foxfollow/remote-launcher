# Example: single-agent — install nginx and verify

The simplest possible workflow. One Claude session, one VM, one task. Useful for first-time users to confirm the launcher works end-to-end.

## Mac layout

```
~/projects/nginx-demo/
└── TASK.md
```

`TASK.md` contents:

```
Install nginx on this VM and confirm it serves the default page on port 80.

Steps:
1. Verify you're on the VM (`hostname` should NOT match my Mac).
2. `sudo apt-get update && sudo apt-get install -y nginx`.
3. Make sure nginx is running. systemd may not be available in this
   environment — if `sudo systemctl status nginx` fails, fall back to
   `sudo nginx -g 'daemon off;' &` or `sudo nginx`.
4. From the VM itself: `curl -s http://localhost/ | head -5`.
5. Report nginx version, PID, and whether the welcome page came back.

Use bash heredocs for any file edits — Read/Edit/Write target my Mac, not the VM.
```

## Run

```bash
remote-launcher myvm --task ~/projects/nginx-demo/TASK.md
```

That's it. Claude reads the task from the system prompt and starts work. Bash commands cross to `myvm` over SSH; everything Anthropic-related stays on your Mac.

## What good output looks like

A short report ending with something like:

```
nginx/1.24.0
PID 1234
curl returned: <h1>Welcome to nginx!</h1>
```

If `hostname` came back as your Mac's name, the wrapper isn't active — re-run via `remote-launcher` (not bare `claude`) and check `remote-launcher-doctor myvm`.

## Pulling artifacts back

The session ran on the VM. To copy files to your Mac:

```bash
scp myvm:/etc/nginx/nginx.conf ~/Downloads/
```
