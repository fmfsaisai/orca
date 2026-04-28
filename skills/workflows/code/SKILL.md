---
name: orca-code
description: Code workflow for Orca lead. Parallel implementation + merge/commit + optimize.
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

When `ORCA_WORKTREE=1`, create a worktree first:

```bash
worktree_path=$(orca-worktree create task-1)
```

When `ORCA_WORKTREE=0`, skip worktree creation — workers use `$ORCA_ROOT` directly and must not commit. The lead reviews and commits the final diff.

```bash
# Short tasks: inline in message
tmux-bridge read <worker> 5 && \
tmux-bridge message <worker> "Task: <description>
Workdir: cd $worktree_path   # or $ORCA_ROOT when worktree is off
Scope: <files to change>
Criteria: <what done looks like>
When done: /review, build, test. Fix issues, then report back." && \
tmux-bridge read <worker> 5 && \
tmux-bridge keys <worker> Enter

# Long-context tasks: write file, send pointer
plan_path="/tmp/orca-handoff-task-1-$(date +%s).md"
cat > "$plan_path" <<PLAN
[full plan with all context, constraints, file refs]
PLAN
tmux-bridge message <worker> "Read $plan_path and execute.
Workdir: cd $worktree_path   # or $ORCA_ROOT when worktree is off
When done: /review, build, test, then report back."
```

Replace `<worker>` with specific label from `$ORCA_WORKERS`.

If more tasks than workers: queue remaining, dispatch when a worker reports done.

## 3. Wait

Say "Dispatched N workers, waiting." and **end turn**.

Worker reports arrive via tmux-bridge message (push). Idle notifications surface on next tool use via heartbeat hook. Idle = no tool calls in 30s — could mean done, stuck, or waiting. Check worker pane to confirm.

## 4. Merge or Commit

For each completed worker:

### Worktree on (`ORCA_WORKTREE=1`)

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

### Worktree off (`ORCA_WORKTREE=0`)

Workers edit `$ORCA_ROOT` directly and do not commit.

```bash
# Review the shared working tree
git diff
git status --short

# Run /simplify on changed files, then inspect again.
git diff

# If clean:
git add <changed-files>
git commit -m "<type>: <description>"
```

**Conflict handling** (worktree mode only):
- Merge in first-done-first-merge order
- Use `--no-commit` to inspect before finalizing
- Auto-resolve trivial conflicts (whitespace, import order)
- Escalate semantic conflicts to user
- After resolving, run `/review` on the integrated result before optimizing

## 5. Optimize

Run `/simplify` on all files changed across workers.

## 6. Report

Summarize to user:
- What was requested vs what was built
- Per-worker summary (1 line each)
- Issues encountered (if any)
- Next steps (if any)
