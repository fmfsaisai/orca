# Multi-Worker Design

How Orca runs N workers in parallel with isolation.

## Model-Agnostic Architecture

Any CLI agent can be lead or worker. Role is determined by `$ORCA_ROLE` env var, not the activation command or binary name.

```
orca --lead claude --worker codex --workers 3 --workflow code

┌─ lead (claude) ──────┬─ w1 (codex) ─┬─ w2 (codex) ─┬─ w3 (codex) ─┐
│ ORCA_ROLE=lead       │ ORCA_ROLE=   │ ORCA_ROLE=   │ ORCA_ROLE=   │
│ ORCA_WORKERS=w1,w2,w3│   worker     │   worker     │   worker     │
│ Skill: orca          │ ORCA_PEER=   │ ORCA_PEER=   │ ORCA_PEER=   │
│                      │   lead       │   lead       │   lead       │
└──────────────────────┴──────────────┴──────────────┴──────────────┘
```

### Why $ORCA_ROLE Instead of Activation Command

Previously: `/orca` = lead, `$orca` = worker. This coupled the role to the agent runtime (Claude Code uses `/`, Codex uses `$`). A Claude Code worker would need to run `/orca` but behave as worker — contradiction.

Now: both agents run the same skill activation for their platform. The skill reads `$ORCA_ROLE` to determine behavior. Any model can be any role.

### Model Command Mapping

`start.sh` maps model names to launch commands:

```
claude  → claude
codex   → codex --sandbox danger-full-access -a on-request ...
gemini  → gemini (future)
<other> → passed through as-is
```

Users can pass custom binaries: `orca --worker ./my-agent`.

## Worktree Isolation

Each worker can operate in an isolated git worktree to avoid file conflicts:

```
project/
  .orca/
    worktree/
      task-1/     # worker 1's isolated copy
      task-2/     # worker 2's isolated copy
    heartbeat/
      1           # worker 1's heartbeat
      2           # worker 2's heartbeat
```

### Lifecycle

1. **Create**: Lead runs `orca-worktree create task-1` → creates `git worktree add .orca/worktree/task-1 -b orca-task-1`
2. **Dispatch**: Lead tells worker to `cd .orca/worktree/task-1`
3. **Work**: Worker operates in isolation, commits to `orca-task-1` branch
4. **Merge**: Lead merges `orca-task-1` into the main branch
5. **Clean**: Lead runs `orca-worktree remove task-1` or `orca stop` cleans all

### Why On-Demand (D5)

Worktrees are created at dispatch time, not at startup:
- User might only use 1 worker (no worktree needed)
- Different tasks need different branch points
- Reduces startup overhead

### Merge Strategy (D2)

For the code workflow: **first-done-first-merge**. As each worker finishes, its worktree branch is merged immediately. This minimizes conflict surface — later merges see earlier workers' changes.

For refactoring: **dependency order** — merge in topological order to maintain coherence.

## Pane Layout

```
tmux even-horizontal layout:

┌─────────┬─────────┬─────────┬─────────┐
│  lead   │  w1     │  w2     │  w3     │
│  pane 0 │  pane 1 │  pane 2 │  pane 3 │
└─────────┴─────────┴─────────┴─────────┘
```

- Named via `tmux-bridge name`: `{session}-lead`, `{session}-worker-1`, etc.
- Per-instance tmux server (D8): `tmux -L orca-{dirname}` isolates from user's tmux
- `SOCKET_PATH` passed to tmux-bridge for out-of-pane naming calls

## Environment Variables

Set by `start.sh` before launching each agent:

| Variable | Lead | Worker |
|----------|------|--------|
| `ORCA` | `1` | `1` |
| `ORCA_ROLE` | `lead` | `worker` |
| `ORCA_PEER` | first worker label | lead label |
| `ORCA_WORKERS` | all worker labels (csv) | - |
| `ORCA_WORKER_ID` | - | `1`, `2`, ... |
| `ORCA_ROOT` | repo root (absolute) | repo root (absolute) |
| `ORCA_WORKFLOW` | workflow name | workflow name |

`ORCA_ROOT` is always the main repo root, even when a worker is in a worktree. This is used by heartbeat hooks to write to the shared `.orca/heartbeat/` directory.

## Codex /clear Monitor

Each Codex worker pane has a background `_skill_monitor` that watches for the Codex welcome banner (after `/clear`). When detected, it re-types `$orca` (or `/orca` for lead) to re-activate the skill.

Monitors use per-pane PID files: `/tmp/orca-monitor-{session}-worker-{i}.pid`.
Cleaned up by `orca stop`.
