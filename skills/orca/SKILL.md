---
name: orca
description: Multi-agent orchestration. Role set by $ORCA_ROLE (lead/worker).
---

# Orca

Environment ready. Do not run any checks.

## Role

Read `$ORCA_ROLE`:
- `lead` — dispatch workers, optimize, report user
- `worker` — implement, self-review, report lead

## Environment

| Variable | Lead | Worker |
|----------|------|--------|
| `ORCA_ROLE` | `lead` | `worker` |
| `ORCA_PEER` | first worker label | lead label |
| `ORCA_WORKERS` | all worker labels (csv) | - |
| `ORCA_WORKER_ID` | - | `1`, `2`, ... |
| `ORCA_ROOT` | repo root | repo root |
| `ORCA_WORKFLOW` | workflow name (optional) | workflow name (optional) |

## Workflow

If `$ORCA_WORKFLOW` is set, invoke the workflow skill after this skill loads:
- `code` → invoke `orca-code` skill (Claude Code: `/orca-code`, Codex: `$orca-code`)

## Communication

One command, always chain with `&&`:

````bash
tmux-bridge read $ORCA_PEER 5 && tmux-bridge message $ORCA_PEER "msg" && tmux-bridge read $ORCA_PEER 5 && tmux-bridge keys $ORCA_PEER Enter
````

Read Guard: must `read` before every `type`/`keys`.

Multi-worker: use specific label from `$ORCA_WORKERS` instead of `$ORCA_PEER`.

## Lead

1. **Confirm** — discuss breakdown with user before dispatching
2. **Dispatch** — for each worker, send: goal, scope, constraints, worktree path. End with: "Run /review, build, test. Fix issues, then report."
   - Single worker: use `$ORCA_PEER`
   - Multi-worker: iterate `$ORCA_WORKERS` (comma-separated), dispatch to each
   - Worktree: run `orca-worktree create <id>` first, tell worker to `cd` into it
   - **Long-context tasks**: write full plan to `/tmp/orca-handoff-<task-slug>-<timestamp>.md` and tell worker to read that path. Survives tmux-bridge truncation and context compaction.
3. **Wait** — say "dispatched, waiting" and **end turn**. Do not poll.
   - Heartbeat: `[orca]` idle notifications surface on lead's next tool use (PreToolUse hook). For immediate awareness, `tmux-bridge read <worker>` to check pane.
   - Idle = no tool calls in 30s. Could mean done, stuck, or waiting. Check worker pane to determine next action.
4. **Optimize** — on report, /simplify changed files
5. **Report** — summarize to user

## Worker

1. **Wait** — reply "Worker ready." in own pane (do not message lead) and end turn
2. **Implement** -> **Self-review** (/review, fix, repeat) -> **Test** (build + tests)
3. **Report** — 1-2 sentence summary to lead, no code/diffs

Workers can also initiate: ask lead for help or confirm approach.

## Rules

1. Read before type/keys
2. One `&&` chain per communication
3. No polling — heartbeat handles idle detection
