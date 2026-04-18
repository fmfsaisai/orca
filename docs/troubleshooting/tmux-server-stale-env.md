# tmux server caches stale env across orca restarts

## Symptom

You edit `~/.bash_profile` (or `~/.zshrc`), comment out an `export FOO=...`,
open a brand-new terminal, run `orca-stop`, then `orca` again — and inside the
new orca panes `echo $FOO` still prints the old value.

This persists across:
- New terminal windows (fresh login shell, profile re-sourced)
- `orca-stop` followed by `orca`
- Reboots of the orca CLI agents (claude / codex)

## Root cause

Two facts compound:

1. **Child processes inherit env at fork time, not at config-edit time.** Once a
   process is running, modifying the file that originally set its env vars has
   no effect — the env is a snapshot.
2. **tmux server is long-lived.** The first time you run `tmux ...` after boot,
   tmux spawns a *server* process that survives until you kill it. Every later
   `tmux` invocation is a *client* that talks to that same server. New
   sessions, new windows, new panes are all forked from the server's
   environment, **not** from the client shell's environment.

So the chain is:

```
First tmux call ever:
  login shell (profile sourced, FOO=old)
    └─ tmux server forked   ← env snapshot taken HERE, FOO=old cached forever
         └─ session A
              └─ pane shell (inherits FOO=old)

Months later, you edit profile and remove FOO:
  new login shell (FOO unset)
    └─ tmux client → talks to existing server (still has FOO=old)
         └─ new session B
              └─ pane shell (inherits FOO=old from server)   ← surprise
```

You can confirm this with:

```bash
tmux show-environment -g | grep FOO
```

The server's `-g` (global) environment is what gets inherited by all new
sessions, and it was frozen at server-spawn time.

## Why orca makes this worse

orca shares the user's main tmux server. So:

- env vars set ages ago for unrelated reasons leak into orca panes
- env vars orca *does* want to refresh (e.g. you just rotated an API key in
  your profile) get masked by the server's stale copy
- `orca-stop` only kills the *session*, not the server, so it doesn't help

## What orca does about it

Orca uses a **per-instance dedicated tmux server** via `tmux -L orca-<dirname>`
(see PLAN.md decision D8).

- `orca` (start.sh) → starts a new server if none exists for this dir, then
  forks the session from *that* server's env, which was just inherited from
  your current login shell
- `orca-stop` → kills the dedicated server entirely (it only owns one session
  anyway), wiping all cached env

Net effect: `orca-stop && orca` always picks up the latest profile state. No
magic, no env-var whitelist, no auto-sync — just a fresh fork chain.

## Workaround for the user's main tmux server

If you hit this in your *own* tmux setup (outside of orca), you have three
options ordered by blast radius:

1. **Surgical** — remove just the stale var from the server's global env:
   ```bash
   tmux set-environment -gu FOO
   ```
   New sessions (existing sessions/panes are unaffected since their pane
   shells already inherited).

2. **Refresh the server's env from your current shell** for a known set of
   vars:
   ```bash
   tmux set-environment -g FOO "$FOO"
   ```

3. **Nuclear** — kill the entire tmux server, losing every session:
   ```bash
   tmux kill-server
   ```

None of these affect already-running processes inside panes; those need to be
restarted to pick up new env.

## Why orca doesn't try to auto-sync env

We considered making orca diff the user's shell env against the server's `-g`
env on each start and patch the differences. Rejected because:

- Choosing *which* vars to sync requires either a brittle whitelist or
  syncing everything (which pollutes tmux internal vars and can break things).
- Already-running CLI agents (claude/codex) wouldn't see the new env anyway —
  they'd need to be restarted, defeating the point of "no-restart sync".
- It introduces magic that contradicts standard Unix behavior, making the
  system harder to reason about.

The dedicated-server approach gives the same end-user guarantee
(`stop && start` = fresh env) with zero magic.
