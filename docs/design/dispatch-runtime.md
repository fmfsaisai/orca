# Dispatch Runtime

Operational detail for Phase 0 of [`orca-evolution-proposal.md`](../research/competitor-analysis/orca-evolution-proposal.md). Decides what `/orca dispatch <task>` actually does inside the host agent.

## Three modes

| Mode | Worker is | IPC |
|---|---|---|
| **M1** workflow-only | the host agent itself, guided by skill text | none |
| **M2** host subagent | one-shot child of the host (cc Task tool) | host's native return channel |
| **M3** tmux pane worker | full agent CLI in a tmux pane (today's model, on-demand) | tmux-bridge |

These coexist. Which one runs is decided per call.

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

**Why not "auto-pick worker model from environment"** (cc in tmux → codex worker; cc outside tmux → cc subagent): same command silently using different models depending on shell context is surprising. Mode is environment-driven; model stays user-driven.

## Capability

| Host | M1 | M2 | M3 |
|---|---|---|---|
| Claude Code | ✅ | ✅ Task tool | ✅ if in tmux |
| Codex | ✅ | ❌ no subagent primitive | ✅ if in tmux |
| other | ✅ | depends | ✅ if in tmux |

Unavailable mode → error with actionable hint, never silent fallback to a different model.

## Tmux nesting

When resolving to M3:

- inside an `orca` tmux session (matches socket `orca-<basename(pwd)>`) → reuse: dispatch via tmux-bridge to an idle worker, or split a new pane
- inside any other tmux → split a pane in the current session, do **not** start a new tmux server (`ux-issues.md` pain #2)
- outside tmux → error per resolution

Implementation: extract `start.sh` pane-split into a callable helper that both `orca` CLI and `/orca dispatch` reuse.

## Heartbeat

- M1 — N/A (host *is* the worker)
- M2 — Task is blocking; no idle concept. Document as an M2 limitation
- M3 — existing PostToolUse → tmux-bridge, unchanged

## Open

1. **Parallel M2** — Claude Code's Task tool can be called multiple times per assistant turn. Need to verify whether those run in parallel or sequentially before promising `--workers N` in M2.
2. **M3 worker termination** — proposal says "die when task completes." Signal source TBD: reuse 30s idle heartbeat, or require explicit `orca worker done`?
3. **M1 default vs. headline value** — Orca's pitch is heterogeneous orchestration. M1-by-default may steer users away from `--worker codex`. Open: should the skill nudge "consider `--worker codex` for parallel review" when about to pick M1?
