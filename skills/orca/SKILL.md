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
| `ORCA_WORKTREE` | `0` or `1` | `0` or `1` |

## Workflow

If `$ORCA_WORKFLOW` is set, invoke the workflow skill after this skill loads:
- `code` → invoke `orca-code` skill (Claude Code: `/orca-code`, Codex: `$orca-code`)

## Communication

One command, always chain with `&&`:

````bash
tmux-bridge read $ORCA_PEER 5 && tmux-bridge message $ORCA_PEER 'msg' && tmux-bridge read $ORCA_PEER 5 && tmux-bridge keys $ORCA_PEER Enter
````

- Read Guard: must `read` before every `type`/`keys`.
- Multi-worker: use specific label from `$ORCA_WORKERS` instead of `$ORCA_PEER`.

**Wrap message body in single quotes.** Inside `'...'`, `$`, backticks, `"`, `\`, and Chinese are literal — safe to send as-is.

**Switch to file delivery only when content contains `'` or newlines.** Applies symmetrically to lead → worker dispatch and worker → lead reports.

````bash
msg_path="/tmp/orca-msg-<slug>-$(date +%s).md"
cat > "$msg_path" <<'EOF'
Body can include 'quotes', real newlines, $vars, `backticks`, code blocks.
EOF
tmux-bridge read $ORCA_PEER 5 && tmux-bridge message $ORCA_PEER "Read $msg_path" && tmux-bridge read $ORCA_PEER 5 && tmux-bridge keys $ORCA_PEER Enter
````

The `"Read $msg_path"` line uses double quotes intentionally — the body is a known-safe template (`Read ` + a controlled variable), so variable expansion is required and there is nothing else to escape. The single-quote default applies to free-form message content.

## Filesystem Access

### Worktree off (`ORCA_WORKTREE=0`)

Workers read and edit files directly in `$ORCA_ROOT`. There is no filesystem isolation, so the lead must avoid editing the worker's scope while the worker is active. Workers do not commit in this mode; the lead reviews the final diff and handles any commit.

| Operation | Path |
|---|---|
| Read or edit tracked files for the task | `$ORCA_ROOT/<path>` |
| Install / build / test | run inside `$ORCA_ROOT` |
| Local untracked files (`.env`, build outputs) | stay in `$ORCA_ROOT`; never reset or remove user-created files unless explicitly asked |

### Worktree on (`ORCA_WORKTREE=1`)

Worktrees share `.git` but have isolated working trees. Tracked files are checked out into every worktree; `.gitignored` resources (`node_modules/`, build outputs, `.env`, manually cloned reference repos under `docs/research/reference-repos/`) do not propagate.

| Operation | Path |
|---|---|
| Read or edit any tracked file for the task (`README.md`, `src/foo.ts`, even `skills/orca/SKILL.md`) | current worktree (`pwd`) |
| Read main repo's `.gitignored` reference material (e.g. cloned reference repos) that doesn't exist in your worktree | `$ORCA_ROOT/<path>` |
| Install / build / test | run inside the worktree (`pnpm install` etc.); package managers reuse their own global cache — do not symlink `node_modules` from main repo |
| Local untracked files (`.env`, build outputs) | stay in current worktree; never write to `$ORCA_ROOT` |
| Write to main repo on purpose (shared docs that bypass the branch, e.g. cross-task research note) | `$ORCA_ROOT/<path>`, only when the task explicitly authorizes it |

See `docs/research/git-worktree-build-practices.md` for sources.

## Lead

1. **Confirm** — discuss breakdown with user before dispatching
2. **Dispatch** — for each worker, send: goal, scope, constraints, and working directory. End with: "Run /review, build, test. Fix issues, then report."
   - Single worker: use `$ORCA_PEER`
   - Multi-worker: iterate `$ORCA_WORKERS` (comma-separated), dispatch to each
   - If `ORCA_WORKTREE=1`: run `orca-worktree create <slug>` first (`<slug>` = kebab-case feature name, e.g. `auth-refactor`; append `-<n>` only when multiple workers share that feature), then tell worker to `cd` into it
   - If `ORCA_WORKTREE=0`: do not create a worktree; tell worker to work directly in `$ORCA_ROOT`
   - Multi-line dispatches use file delivery (see Communication). Path-only message keeps worker context lean and survives compaction.
3. **Wait** — say "dispatched, waiting" and **end turn**. Do not poll.
   - Heartbeat: `[orca]` idle notifications surface on lead's next tool use (PreToolUse hook). For immediate awareness, `tmux-bridge read <worker>` to check pane.
   - Idle = no tool calls in 30s. Could mean done, stuck, or waiting. Check worker pane to determine next action.
4. **Optimize** — on report, /simplify changed files
5. **Report** — summarize to user

## Worker

1. **Wait** — reply "Worker ready." in own pane (do not message lead) and end turn
2. **Implement** -> **Self-review** (/review, fix, repeat) -> **Test** (build + tests)
3. **Commit** — only when `ORCA_WORKTREE=1` and the dispatch asks for it. When `ORCA_WORKTREE=0`, do not commit; leave the diff for the lead.
4. **Report** — 1-2 sentence summary to lead, no code/diffs (see Communication for inline vs file)

Workers can also initiate: ask lead for help or confirm approach.

## Rules

1. Read before type/keys
2. One `&&` chain per communication
3. No polling — heartbeat handles idle detection
