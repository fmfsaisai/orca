# Dispatch Runtime

Technical mechanics for `/orca dispatch <task>`. Phase goals + sub-phase tasking live in [`PLAN.md`](../../PLAN.md) Phase E0; this doc owns the per-call resolution model.

## Three modes

| Mode | Worker is | IPC |
|---|---|---|
| **M1** workflow-only | host agent itself, guided by skill text | none |
| **M2** host subagent | one-shot child of host (cc Task tool) | host's native return channel |
| **M3** tmux pane worker | full agent CLI in a tmux pane (today's model, on-demand) | tmux-bridge |

These coexist; per-call resolution decides which one runs.

## Resolution

```
/orca dispatch <task> [--workers N] [--worker MODEL] [--mode auto|m1|m2|m3]

mode = explicit --mode if given, else first match top-down:

  workers > 1                              → M3
  worker MODEL ≠ host agent                → M3
  M3 needed but not in tmux                → error: "needs tmux, or use --worker <host>"
  worker = host AND host has subagent API  → M2
  default                                  → M1
```

Mode is environment-driven; *worker model* stays user-driven (no silent model swap based on `$TMUX`).

## Capability

| Host | M1 | M2 | M3 |
|---|---|---|---|
| Claude Code | ✅ | ✅ Task tool | ✅ if in tmux |
| Codex | ✅ | ❌ no subagent primitive | ✅ if in tmux |
| other | ✅ | depends | ✅ if in tmux |

Unavailable mode → error with actionable hint, never silent fallback to a different model.

## tmux nesting (M3 path)

- inside an `orca` tmux session (socket `orca-<basename(pwd)>`) → reuse: dispatch via tmux-bridge to an idle worker, or split a new pane
- inside any other tmux → split a pane in current session, do **not** spawn a new tmux server (User Feedback #2)
- outside tmux → error per resolution

Implementation: extract `start.sh` pane-split into a callable helper that both `orca` CLI and `/orca dispatch` reuse.

## Heartbeat per mode

- M1 — N/A (host *is* the worker)
- M2 — Task is blocking; no idle concept. Documented limitation.
- M3 — existing PostToolUse → tmux-bridge, unchanged.

## Open

1. **Parallel M2** — cc's Task tool can be called multiple times per assistant turn. Verify whether those run in parallel before promising `--workers N` in M2.
2. **M3 worker termination signal** — proposal says "die when task completes." Reuse 30s idle heartbeat, or require explicit `orca worker done`?
3. **M1 default vs. headline value** — Orca's pitch is heterogeneous orchestration; M1-by-default may steer users away from `--worker codex`. Should the skill nudge "consider `--worker codex` for parallel review" before falling into M1?
