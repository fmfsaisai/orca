# AGENTS.md

Orca — Model-agnostic multi-agent orchestrator. Shell + Skills.

Lead (configurable model) dispatches workers (configurable model) via tmux-bridge.

## Structure

```
start.sh            → tmux session + panes
stop.sh             → session cleanup
install.sh          → smux + commands + skill + hooks
skills/orca/   → shared skill (lead + worker)
docs/               → architecture decisions
```

## Rules

- English comments and output
- Shell: `set -euo pipefail`, quote variables
- Commits: `<type>: <description>`
- Git in worktrees: prefer `git -C <repo-path>` over `cd <worktree> && git ...` for HEAD-affecting commands (`checkout`, `reset`, `merge`). A `cd` chain makes it trivial to mutate the wrong worktree's HEAD.
