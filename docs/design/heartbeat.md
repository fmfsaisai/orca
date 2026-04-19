# Heartbeat Design

How Orca detects worker idle/completion without polling.

## Problem

After lead dispatches workers and says "waiting, end turn", it needs to know when workers finish. Options considered:

| Approach | Pros | Cons |
|----------|------|------|
| Poll worker panes every Ns | Simple | Burns tokens, false positives on thinking pauses |
| Worker sends tmux-bridge message on done | True push | Only catches explicit "I'm done" — misses stuck/crashed workers |
| PostToolUse hook fires every tool call | Too noisy | Floods lead with irrelevant notifications |
| **Heartbeat file + PreToolUse check** | Low-overhead, catches idle | Notifications delayed until lead's next tool use |

**Chosen**: Heartbeat files + hook-based check (D1 in PLAN.md).

## How It Works

```
Worker side (PostToolUse hook):
  Every tool call → write timestamp to .orca/heartbeat/<worker-id>

Lead side (PreToolUse hook):
  Every tool call → read .orca/heartbeat/*, check age
  If any worker's timestamp > 30s old → output "[orca] Idle: worker-1(45s)"
```

### Worker: `hooks/post-tool-use.sh`

Fires after every tool call on workers. Pure file write, ~1ms, zero tokens:

```bash
[[ "${ORCA_ROLE:-}" != "worker" ]] && exit 0
date +%s > "${ORCA_ROOT:-.}/.orca/heartbeat/${ORCA_WORKER_ID:-0}"
```

### Lead: `hooks/check-heartbeat.sh`

Fires before every tool call on lead. Reads timestamps, outputs notification if idle:

```bash
[[ "${ORCA_ROLE:-}" != "lead" ]] && exit 0
# Check each worker's heartbeat age
# Output "[orca] Idle: worker-1(45s)" or "[orca] All 3 workers idle: ..."
```

The output appears in lead's context, so the LLM sees it and can act.

## Limitations

**Notifications are not real-time.** They surface only when lead uses a tool. If lead is idle (waiting, no tool calls), it won't see heartbeat updates until the user or a worker triggers it.

This is acceptable because:
1. **Primary notification is push**: workers report done via `tmux-bridge message` — this IS real-time
2. **Heartbeat is supplementary**: it tells lead "workers you haven't heard from are also idle" — useful after the first worker reports
3. **Background monitor deferred to P3**: would add complexity and tmux-bridge race conditions

**Idle ≠ done.** A worker idle for 30s could mean:
- Finished and waiting for next task
- Stuck on an error
- Waiting for user input (modal prompt)
- Thinking long (no tool call in a while)

Lead must `tmux-bridge read <worker>` to inspect the pane and determine actual state.

## File Layout

```
.orca/
  heartbeat/
    1          # worker 1's last tool-use timestamp (epoch seconds)
    2          # worker 2's
    3          # worker 3's
```

Cleaned up by `orca stop` (rm -rf .orca/heartbeat).

## Why Not a Background Monitor?

A background process (like `_skill_monitor` for Codex /clear) that watches heartbeats and sends tmux-bridge notifications to lead would provide real-time idle detection. We chose not to do this in P0 because:

1. **Race condition**: if lead is mid-output when the monitor sends a message, text gets garbled
2. **Complexity**: another background process to manage, PID files, lifecycle
3. **Diminishing returns**: the push-based worker report covers the happy path; heartbeat is for edge cases

Planned for P3: Worker Lifecycle, where we can implement it with proper buffering/queuing.
