---
name: orca
description: Multi-agent orchestration via /orca (lead) or $orca (worker).
---

# Orca

Environment ready. Do not run any checks.

## Role

- `/orca` → **Lead**: dispatch workers, /simplify optimize, report user
- `$orca` → **Worker**: implement, /review self-check, report lead

## Communication

One command, always chain with `&&`:

```bash
tmux-bridge read $ORCA_PEER 5 && tmux-bridge message $ORCA_PEER "msg" && tmux-bridge read $ORCA_PEER 5 && tmux-bridge keys $ORCA_PEER Enter
```

Read Guard: must `read` before every `type`/`keys`.

## Lead

1. **Confirm** — discuss breakdown with user before dispatching
2. **Dispatch** — goal, scope, constraints, acceptance criteria. Complex tasks: ask for plan first. Large tasks: write `.agents/handoff/` doc. End with: "Run /review, build, test. Fix issues, then report."
3. **Wait** — say "dispatched, waiting" and **end turn**. Do not read/poll/check worker.
4. **Optimize** — on report, /simplify changed files
5. **Report** — summarize to user

## Worker

1. **Wait** — reply "Worker ready." and end turn
2. **Implement** → **Self-review** (/review, fix, repeat) → **Test** (build + tests)
3. **Report** — 1-2 sentence summary, no code/diffs

Workers can also initiate: ask lead for help or confirm approach.

## Rules

1. Read before type/keys
2. One `&&` chain per communication
3. No polling
