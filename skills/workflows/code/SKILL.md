---
name: orca-code
description: Code workflow for Orca lead. Parallel implementation + merge + optimize.
---

# Code Workflow

For lead only. If `$ORCA_ROLE` != `lead`, ignore this workflow.

Activated via `--workflow code` or invoke `orca-code` skill manually.

## 1. Plan

Break the user's request into independent sub-tasks. Each task must:
- Touch different files/modules (no overlap between workers)
- Be completable by one worker in isolation
- Have clear scope and acceptance criteria

Confirm breakdown with user before dispatching.

## 2. Dispatch

For each task, up to N workers (from `$ORCA_WORKERS`):

```bash
# 1. Create isolated worktree
worktree_path=$(orca-worktree create task-1)

# 2. Short tasks: inline in message
tmux-bridge read <worker> 5 && \
tmux-bridge message <worker> "Task: <description>
Worktree: cd $worktree_path
Scope: <files to change>
Criteria: <what done looks like>
When done: /review, build, test. Fix issues, then report back." && \
tmux-bridge read <worker> 5 && \
tmux-bridge keys <worker> Enter

# 3. Long-context tasks: write file, send pointer
plan_path="/tmp/orca-handoff-task-1-$(date +%s).md"
cat > "$plan_path" <<PLAN
[full plan with all context, constraints, file refs]
PLAN
tmux-bridge message <worker> "Read $plan_path and execute.
Worktree: cd $worktree_path
When done: /review, build, test, then report back."
```

Replace `<worker>` with specific label from `$ORCA_WORKERS`.

If more tasks than workers: queue remaining, dispatch when a worker reports done.

## 3. Wait

Say "Dispatched N workers, waiting." and **end turn**.

Worker reports arrive via tmux-bridge message (push). Idle notifications surface on next tool use via heartbeat hook. Idle = no tool calls in 30s — could mean done, stuck, or waiting. Check worker pane to confirm.

## 4. Merge

First-done-first-merge. For each completed worker:

```bash
# Detect base branch
base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
base_branch="${base_branch:-main}"

# Review changes
git -C .orca/worktree/task-1 log --oneline "$base_branch..HEAD"
git -C .orca/worktree/task-1 diff "$base_branch"

# Merge into current branch
git merge --no-commit orca-task-1

# Inspect staged changes. If clean:
git commit -m "merge: task-1 from worker"

# Clean up
orca-worktree remove task-1
```

**Conflict handling:**
- Merge in first-done-first-merge order
- Use `--no-commit` to inspect before finalizing
- Auto-resolve trivial conflicts (whitespace, import order)
- Escalate semantic conflicts to user
- After resolving, run `/review` on merged result before optimizing

## 5. Optimize

Run `/simplify` on all files changed across workers.

## 6. Report

Summarize to user:
- What was requested vs what was built
- Per-worker summary (1 line each)
- Issues encountered (if any)
- Next steps (if any)
