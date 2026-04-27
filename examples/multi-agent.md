# Example: multi-agent — three roles, one VM

A small multi-agent pattern: one **init** agent prepares the environment, two **worker** agents run in parallel doing independent jobs, one **reviewer** agent collects the results. All against the same remote VM.

This is the same shape used in larger multi-agent labs, just trimmed to be readable.

## Mac layout

```
~/projects/multi-demo/
└── MASTER.md
```

`MASTER.md` (a single file shared by all sessions; each agent reads its own role from the heading you paste):

````markdown
# Shared task: build two static sites and a status page

Workspace on the VM: `~/multi-demo/`. All agents work under there.

## Agent 0 — Init (run first, alone)

1. `mkdir -p ~/multi-demo/{site-a,site-b,status}` and `cd ~/multi-demo`.
2. Write `~/multi-demo/README.md` describing the layout (one paragraph).
3. Print `READY FOR WORKERS` when done.

## Agent 1 — Worker A (run in parallel with Agent 2)

Build `~/multi-demo/site-a/index.html`: a single page with title
"Site A", an `<h1>`, and the current date. Validate that the file
exists and has more than 5 lines. Do NOT touch `site-b/` or `status/`.

Print `AGENT 1 DONE` when finished.

## Agent 2 — Worker B (run in parallel with Agent 1)

Same as Agent 1 but for `~/multi-demo/site-b/index.html` with title
"Site B". Do NOT touch `site-a/` or `status/`.

Print `AGENT 2 DONE` when finished.

## Agent 3 — Reviewer (run last, alone)

Wait until both `site-a/index.html` and `site-b/index.html` exist
(they should — Agents 1 and 2 finished before you started). Build
`~/multi-demo/status/index.html` listing both pages with `wc -l` for
each. If either source page is missing, STOP and report.

Print `=== DEMO COMPLETE ===` when finished.

## Rules for everyone

- Use bash heredocs (`cat > path <<'EOF' ... EOF`) for VM-side files.
  Read/Edit/Write target the Mac, not the VM.
- Stay strictly inside your assigned subdirectory.
- If a self-test fails because a peer hasn't finished — STOP and ask,
  do not try to do their work.
````

## Run

### Terminal 1 — Agent 0

```bash
remote-launcher myvm --task ~/projects/multi-demo/MASTER.md
```

In Claude:
> You are Agent 0.

Wait for `READY FOR WORKERS`. Then quit (`/exit`) or leave it open.

### Terminals 2 and 3 — Agents 1 and 2 (in parallel)

In each:

```bash
remote-launcher myvm --task ~/projects/multi-demo/MASTER.md
```

Then in each Claude session, respectively:
> You are Agent 1.
>
> You are Agent 2.

Wait for both to print their `DONE` line.

### Terminal 4 — Agent 3 (the reviewer)

```bash
remote-launcher myvm --task ~/projects/multi-demo/MASTER.md
```

> You are Agent 3.

Wait for `=== DEMO COMPLETE ===`.

### Pull artifacts back to your Mac

```bash
scp -r myvm:~/multi-demo ~/Downloads/
open ~/Downloads/multi-demo/status/index.html
```

## Why this works

- 4 `remote-launcher` processes on the Mac, each with its own `claude`
  process and context window. Anthropic credentials stay on the Mac.
- All sessions share the VM filesystem; isolation between agents is at
  the prompt level (each agent has a clearly scoped subdirectory).
- Each `remote-launcher` invocation has its own SSH ControlMaster
  (one socket per session). A small VM handles 4–6 concurrent SSH
  sessions comfortably.

## Scaling up

The same pattern works with N parallel workers and a multi-step
finalizer. Keep the rules consistent: one shared MASTER.md, each agent
has a strict scope, sequential phases happen in dedicated terminals,
parallel phases happen simultaneously.
