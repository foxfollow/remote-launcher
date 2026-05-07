# Example: multi-host — one agent, web VM + DB VM

One Claude session coordinating across two VMs at the same time. The agent
installs nginx on the web VM and PostgreSQL on the DB VM, opens connectivity
between them, and verifies end-to-end. Routing is via the `@<host>` prefix in
each Bash call.

## Mac layout

```
~/projects/web-db-demo/
└── TASK.md
```

`TASK.md` contents:

```
You have two remote hosts in this session:

- `webvm` — default. nginx will live here.
- `dbvm`  — PostgreSQL will live here.

Goals:
1. Install and start nginx on @webvm. Default site should answer on port 80.
2. Install PostgreSQL on @dbvm. Create role `app` with password `app` and
   database `appdb` owned by `app`. Listen on the dbvm's primary IPv4
   interface (not just localhost) and allow `app@<webvm-ip>` over `md5` in
   pg_hba.conf.
3. From @webvm, install `postgresql-client` and verify the connection:
   `PGPASSWORD=app psql -h <dbvm-ip> -U app -d appdb -c 'select now();'`.
4. Report:
   - nginx version + PID on webvm
   - psql server version on dbvm
   - whether the cross-host connect succeeded
   - hostname of each host (so I can confirm they really are two VMs)

Routing reminders:
- Prefix EVERY Bash call with `@webvm` or `@dbvm`. Don't rely on the default
  here — being explicit prevents accidents.
- Filesystems are NOT shared. To move a file from one host to the other,
  use `scp host1:/path host2:/path` (or pull to the Mac and push back).
- `cd /etc` on one host has no effect on the other.
- DO NOT install nginx on dbvm or postgres on webvm. Stay in role.
```

## Run

```bash
remote-launcher webvm --host dbvm --task ~/projects/web-db-demo/TASK.md
```

The launcher prints the host roster and the per-host shell mode at startup,
e.g.:

```
[remote-launcher] testing SSH to webvm...
[remote-launcher] webvm shell: posix
[remote-launcher] testing SSH to dbvm...
[remote-launcher] dbvm shell: posix
[remote-launcher] launching Claude Code (session …); bash → webvm dbvm (default: webvm)
[remote-launcher] route via @<host> prefix in Bash; unprefixed → webvm
```

## What good output looks like

```
@webvm hostname → web-vm-1
@dbvm  hostname → db-vm-1

nginx/1.24.0 (webvm), PID 1234
PostgreSQL 16.x (dbvm)
cross-host SELECT now() → 2026-05-07 12:34:56+00
```

## Common mistakes the agent might make

- **Forgetting `@host` prefix.** Without it the command goes to the default
  (`webvm`). If the agent runs `apt-get install postgresql` without a prefix,
  it lands on the wrong host. Encourage it to always prefix.
- **Assuming a shared filesystem.** Writing a file to `/etc/postgresql/...`
  on dbvm doesn't appear on webvm. Inter-host data movement is explicit.
- **Cross-host `cd` confusion.** Each host tracks its own working directory.

## Pulling artifacts back

```bash
scp webvm:/etc/nginx/nginx.conf       ~/Downloads/
scp dbvm:/etc/postgresql/16/main/postgresql.conf ~/Downloads/
```
