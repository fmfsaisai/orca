# P0: Multi-Worker + Isolation + Hooks

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Multi-worker orchestration with worktree isolation and heartbeat-based idle detection.

**Architecture:** start.sh gains `--workers/--lead/--worker/--workflow` flags, creates N worker panes. Workers get isolated git worktrees on demand. PostToolUse hooks write heartbeat timestamps; lead's PreToolUse hook checks heartbeats and surfaces idle notifications. Role determined by `$ORCA_ROLE` env var (not activation command).

**Tech Stack:** bash, tmux, tmux-bridge (smux), git worktree

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `start.sh` | CLI args, model mapping, multi-worker pane creation, monitors |
| Modify | `stop.sh` | Worktree cleanup, multi-monitor PID cleanup |
| Modify | `install.sh` | Register orca-worktree command, PostToolUse/PreToolUse hooks |
| Modify | `skills/orca/SKILL.md` | Role from `$ORCA_ROLE`, multi-worker dispatch, heartbeat |
| Create | `orca-worktree.sh` | git worktree create/remove/list/clean |
| Create | `hooks/post-tool-use.sh` | Worker heartbeat: write timestamp |
| Create | `hooks/check-heartbeat.sh` | Lead notification: check idle workers |

---

### Task 1: start.sh — CLI args + model mapping + multi-worker

**Files:**
- Modify: `start.sh`

- [ ] **Step 1: Rewrite start.sh with CLI arg parsing and multi-worker support**

Replace entire start.sh:

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Defaults ---
WORKERS=1
LEAD_MODEL="claude"
WORKER_MODEL="codex"
WORKFLOW=""

# --- Usage ---
usage() {
  cat <<EOF
Usage: orca [OPTIONS]

Options:
  --workers N, -n N    Number of workers (default: 1)
  --lead MODEL         Lead model (default: claude)
  --worker MODEL       Worker model (default: codex)
  --workflow NAME, -w  Workflow skill to load
  -h, --help           Show this help
EOF
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workers|-n) WORKERS="$2"; shift 2 ;;
    --lead)       LEAD_MODEL="$2"; shift 2 ;;
    --worker)     WORKER_MODEL="$2"; shift 2 ;;
    --workflow|-w) WORKFLOW="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

SESSION="orca-$(basename "$(pwd)")"

# --- Model command mapping ---
model_cmd() {
  case "$1" in
    claude) echo "claude" ;;
    codex)  echo "codex --sandbox danger-full-access -a on-request -c features.codex_hooks=true" ;;
    *)      echo "$1" ;;
  esac
}

# --- Launch agent in pane ---
launch_agent() {
  local pane="$1" model="$2" role="$3"
  local cmd
  cmd=$(model_cmd "$model")
  case "$model" in
    codex)
      local skill_cmd="\$orca"
      [[ "$role" == "lead" ]] && skill_cmd="/orca"
      tmux send-keys -t "$pane" "$cmd '$skill_cmd'" Enter
      ;;
    *)
      tmux send-keys -t "$pane" "$cmd" Enter
      ;;
  esac
}

# --- Prerequisites ---
for bin in tmux tmux-bridge; do
  if ! command -v "$bin" &>/dev/null; then
    echo "Error: $bin not installed" >&2
    exit 1
  fi
done

check_model() {
  local bin
  bin=$(model_cmd "$1" | awk '{print $1}')
  if ! command -v "$bin" &>/dev/null; then
    echo "Error: $bin not installed" >&2
    exit 1
  fi
}
check_model "$LEAD_MODEL"
check_model "$WORKER_MODEL"

# --- Reattach if exists ---
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux attach -t "$SESSION"
  exit 0
fi

# --- Working directory ---
WORKDIR="${ORCA_WORKDIR:-$(pwd)}"

# --- Info ---
echo "Starting $SESSION ..."
echo "  Lead:     $(model_cmd "$LEAD_MODEL") (x1)"
echo "  Worker:   $(model_cmd "$WORKER_MODEL") (x$WORKERS)"
[[ -n "$WORKFLOW" ]] && echo "  Workflow: $WORKFLOW"
echo "  Dir:      $WORKDIR"

# --- Create session with lead pane ---
tmux new-session -d -s "$SESSION" -n main -c "$WORKDIR"

LEAD_LABEL="${SESSION}-lead"
tmux-bridge name "$SESSION:main.0" "$LEAD_LABEL"

# --- Create worker panes ---
WORKER_LABELS=()
for i in $(seq 1 "$WORKERS"); do
  tmux split-window -h -t "$SESSION:main" -c "$WORKDIR"
  label="${SESSION}-worker-${i}"
  WORKER_LABELS+=("$label")
  tmux-bridge name "$SESSION:main.${i}" "$label"
done

# --- Layout + config ---
tmux select-layout -t "$SESSION:main" even-horizontal
tmux set-option -t "$SESSION" mode-keys vi
tmux set-option -t "$SESSION" mouse on
tmux bind-key Space select-layout even-horizontal

# --- Inject env + launch workers ---
WORKERS_CSV=$(IFS=,; echo "${WORKER_LABELS[*]}")

for i in $(seq 1 "$WORKERS"); do
  pane="$SESSION:main.${i}"
  env_cmd="export ORCA=1 ORCA_ROLE=worker ORCA_PEER=$LEAD_LABEL ORCA_WORKER_ID=$i ORCA_ROOT=$WORKDIR"
  [[ -n "$WORKFLOW" ]] && env_cmd="$env_cmd ORCA_WORKFLOW=$WORKFLOW"
  tmux send-keys -t "$pane" "$env_cmd" Enter
  launch_agent "$pane" "$WORKER_MODEL" "worker"
done

# --- Inject env + launch lead ---
env_cmd="export ORCA=1 ORCA_ROLE=lead ORCA_WORKERS=$WORKERS_CSV ORCA_PEER=${WORKER_LABELS[0]} ORCA_ROOT=$WORKDIR"
[[ -n "$WORKFLOW" ]] && env_cmd="$env_cmd ORCA_WORKFLOW=$WORKFLOW"
tmux send-keys -t "$SESSION:main.0" "$env_cmd" Enter
launch_agent "$SESSION:main.0" "$LEAD_MODEL" "lead"

# --- Codex /clear re-activation monitors ---
_skill_monitor() {
  set +e
  local session="$1" pane="$2" role="$3"
  local skill_cmd="\$orca"
  [[ "$role" == "lead" ]] && skill_cmd="/orca"

  while tmux has-session -t "$session" 2>/dev/null; do
    local out banner
    out=$(tmux capture-pane -p -t "$pane" 2>/dev/null \
      | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g') || true
    banner=$(echo "$out" | grep -c '>_ OpenAI Codex')
    if [ "$banner" -gt 0 ] && ! echo "$out" | grep -q "$skill_cmd"; then
      sleep 2
      tmux send-keys -l -t "$pane" "$skill_cmd"
    fi
    sleep 3
  done
}

# Kill old monitors
for f in /tmp/orca-monitor-"${SESSION}"-*.pid; do
  if [[ -f "$f" ]]; then
    kill "$(cat "$f")" 2>/dev/null || true
    rm -f "$f"
  fi
done

# Start monitors for Codex panes
if [[ "$WORKER_MODEL" == "codex" ]]; then
  for i in $(seq 1 "$WORKERS"); do
    _skill_monitor "$SESSION" "$SESSION:main.${i}" "worker" &
    echo $! > "/tmp/orca-monitor-${SESSION}-worker-${i}.pid"
  done
fi

if [[ "$LEAD_MODEL" == "codex" ]]; then
  _skill_monitor "$SESSION" "$SESSION:main.0" "lead" &
  echo $! > "/tmp/orca-monitor-${SESSION}-lead.pid"
fi

# --- Focus lead + attach ---
tmux select-pane -t "$SESSION:main.0"
tmux attach -t "$SESSION"
```

- [ ] **Step 2: Run shellcheck**

Run: `shellcheck start.sh`
Expected: no errors (warnings about `SC2207` for array assignment OK)

- [ ] **Step 3: Commit**

```bash
git add start.sh
git commit -m "feat: start.sh multi-worker support with --workers/--lead/--worker/--workflow"
```

---

### Task 2: orca-worktree.sh

**Files:**
- Create: `orca-worktree.sh`

- [ ] **Step 1: Create orca-worktree.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ORCA_DIR="${ORCA_ROOT:-.}/.orca/worktree"

usage() {
  cat <<EOF
Usage: orca-worktree {create|remove|list|clean} [id]

Commands:
  create <id>   Create worktree at .orca/worktree/<id>
  remove <id>   Remove worktree and its branch
  list          List orca worktrees
  clean         Remove all orca worktrees
EOF
}

cmd="${1:-}"
id="${2:-}"

case "$cmd" in
  create)
    [[ -z "$id" ]] && { echo "Error: id required" >&2; usage; exit 1; }
    dir="$ORCA_DIR/$id"
    branch="orca-${id}"
    mkdir -p "$(dirname "$dir")"
    git worktree add "$dir" -b "$branch"
    echo "$dir"
    ;;
  remove)
    [[ -z "$id" ]] && { echo "Error: id required" >&2; usage; exit 1; }
    dir="$ORCA_DIR/$id"
    git worktree remove "$dir" --force 2>/dev/null || true
    git branch -D "orca-${id}" 2>/dev/null || true
    echo "Removed $dir"
    ;;
  list)
    git worktree list | grep "\.orca/worktree" || echo "No orca worktrees"
    ;;
  clean)
    local count=0
    while IFS= read -r wt; do
      [[ -z "$wt" ]] && continue
      git worktree remove "$wt" --force 2>/dev/null || true
      # Extract branch name from worktree path
      local wt_id
      wt_id=$(basename "$wt")
      git branch -D "orca-${wt_id}" 2>/dev/null || true
      count=$((count + 1))
    done < <(git worktree list --porcelain | grep "^worktree.*\.orca/worktree" | sed 's/^worktree //')
    echo "Cleaned $count worktree(s)"
    ;;
  *)
    usage
    [[ -z "$cmd" ]] && exit 0
    exit 1
    ;;
esac
```

Note: `local` inside `case` outside function won't work. Fix: move `clean` logic to avoid `local`:

```bash
  clean)
    count=0
    while IFS= read -r wt; do
      [[ -z "$wt" ]] && continue
      git worktree remove "$wt" --force 2>/dev/null || true
      wt_id=$(basename "$wt")
      git branch -D "orca-${wt_id}" 2>/dev/null || true
      count=$((count + 1))
    done < <(git worktree list --porcelain | grep "^worktree.*\.orca/worktree" | sed 's/^worktree //')
    echo "Cleaned $count worktree(s)"
    ;;
```

- [ ] **Step 2: Make executable + shellcheck**

Run: `chmod +x orca-worktree.sh && shellcheck orca-worktree.sh`

- [ ] **Step 3: Commit**

```bash
git add orca-worktree.sh
git commit -m "feat: orca-worktree helper for git worktree management"
```

---

### Task 3: stop.sh — worktree + multi-monitor cleanup

**Files:**
- Modify: `stop.sh`

- [ ] **Step 1: Update stop.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SESSION="orca-$(basename "$(pwd)")"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' does not exist"
  exit 0
fi

echo "Panes in $SESSION:"
tmux list-panes -t "$SESSION" -F "  #{pane_index}: #{pane_current_command} (pid: #{pane_pid})"

echo ""
read -rp "Stop $SESSION? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Cancelled"
  exit 0
fi

# Kill all monitors for this session
for f in /tmp/orca-monitor-"${SESSION}"-*.pid; do
  if [[ -f "$f" ]]; then
    kill "$(cat "$f")" 2>/dev/null || true
    rm -f "$f"
  fi
done

# Clean worktrees
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -x "$SCRIPT_DIR/orca-worktree.sh" ]]; then
  "$SCRIPT_DIR/orca-worktree.sh" clean 2>/dev/null || true
fi

# Clean heartbeat state
rm -rf .orca/heartbeat 2>/dev/null || true

tmux kill-session -t "$SESSION"
echo "Stopped $SESSION"
```

- [ ] **Step 2: shellcheck**

Run: `shellcheck stop.sh`

- [ ] **Step 3: Commit**

```bash
git add stop.sh
git commit -m "feat: stop.sh worktree cleanup and multi-monitor PID cleanup"
```

---

### Task 4: hooks/ — heartbeat + idle check

**Files:**
- Create: `hooks/post-tool-use.sh` (worker heartbeat)
- Create: `hooks/check-heartbeat.sh` (lead idle check)

- [ ] **Step 1: Create hooks/post-tool-use.sh**

```bash
#!/usr/bin/env bash
# PostToolUse hook: worker writes heartbeat timestamp.
# Runs after every tool call. Fast — just a file write.
[[ -z "${ORCA:-}" ]] && exit 0
[[ "${ORCA_ROLE:-}" != "worker" ]] && exit 0

HEARTBEAT_DIR="${ORCA_ROOT:-.}/.orca/heartbeat"
mkdir -p "$HEARTBEAT_DIR"
date +%s > "$HEARTBEAT_DIR/${ORCA_WORKER_ID:-0}"
```

- [ ] **Step 2: Create hooks/check-heartbeat.sh**

```bash
#!/usr/bin/env bash
# PreToolUse hook: lead checks worker heartbeats before each tool call.
# Outputs notification if any worker idle >30s.
[[ -z "${ORCA:-}" ]] && exit 0
[[ "${ORCA_ROLE:-}" != "lead" ]] && exit 0

HEARTBEAT_DIR="${ORCA_ROOT:-.}/.orca/heartbeat"
[[ ! -d "$HEARTBEAT_DIR" ]] && exit 0

COOLDOWN=30
now=$(date +%s)
idle_workers=()
total=0

for f in "$HEARTBEAT_DIR"/[0-9]*; do
  [[ -f "$f" ]] || continue
  total=$((total + 1))
  last=$(cat "$f")
  gap=$((now - last))
  id=$(basename "$f")
  if (( gap > COOLDOWN )); then
    idle_workers+=("worker-$id(${gap}s)")
  fi
done

if (( ${#idle_workers[@]} > 0 )); then
  if (( ${#idle_workers[@]} == total )); then
    echo "[orca] All $total workers idle: ${idle_workers[*]}"
  else
    echo "[orca] Idle: ${idle_workers[*]}"
  fi
fi
```

- [ ] **Step 3: Make executable + shellcheck**

Run: `chmod +x hooks/post-tool-use.sh hooks/check-heartbeat.sh && shellcheck hooks/post-tool-use.sh hooks/check-heartbeat.sh`

- [ ] **Step 4: Commit**

```bash
git add hooks/
git commit -m "feat: heartbeat hooks — worker PostToolUse + lead PreToolUse idle check"
```

---

### Task 5: install.sh — register new commands + hooks

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Add orca-worktree command registration**

After the existing `ln -sfn` block for global commands, add:

```bash
ln -sfn "$SCRIPT_DIR/orca-worktree.sh" ~/.local/bin/orca-worktree
echo "[x] Global commands: orca, orca-stop, orca-idle, orca-worktree -> ~/.local/bin/"
```

(Update the existing echo line to include orca-worktree.)

- [ ] **Step 2: Add PostToolUse hook for workers (CC)**

After the existing SessionStart hook registration for Claude Code, add PostToolUse hook:

```bash
# Claude Code PostToolUse hook (worker heartbeat)
if jq -e '.hooks.PostToolUse' "$CLAUDE_SETTINGS" &>/dev/null; then
  echo "[x] Claude Code PostToolUse hook exists, skipping"
else
  POST_HOOK_TMP=$(mktemp)
  cat > "$POST_HOOK_TMP" << HOOKEOF
[{"hooks":[{"type":"command","command":"$SCRIPT_DIR/hooks/post-tool-use.sh"}]}]
HOOKEOF
  jq --slurpfile hook "$POST_HOOK_TMP" '.hooks.PostToolUse = $hook[0]' \
    "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp" && mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
  rm -f "$POST_HOOK_TMP"
  echo "[x] Claude Code PostToolUse hook registered (worker heartbeat)"
fi
```

- [ ] **Step 3: Add PreToolUse hook for lead (CC)**

```bash
# Claude Code PreToolUse hook (lead heartbeat check)
if jq -e '.hooks.PreToolUse' "$CLAUDE_SETTINGS" &>/dev/null; then
  echo "[x] Claude Code PreToolUse hook exists, skipping"
else
  PRE_HOOK_TMP=$(mktemp)
  cat > "$PRE_HOOK_TMP" << HOOKEOF
[{"hooks":[{"type":"command","command":"$SCRIPT_DIR/hooks/check-heartbeat.sh"}]}]
HOOKEOF
  jq --slurpfile hook "$PRE_HOOK_TMP" '.hooks.PreToolUse = $hook[0]' \
    "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp" && mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
  rm -f "$PRE_HOOK_TMP"
  echo "[x] Claude Code PreToolUse hook registered (lead heartbeat check)"
fi
```

- [ ] **Step 4: Add hooks for Codex**

Similar to CC but writes to `~/.codex/hooks.json`:

```bash
# Codex PostToolUse hook
if ! jq -e '.hooks.PostToolUse' "$CODEX_HOOKS" &>/dev/null; then
  POST_HOOK_TMP=$(mktemp)
  cat > "$POST_HOOK_TMP" << HOOKEOF
[{"hooks":[{"type":"command","command":"$SCRIPT_DIR/hooks/post-tool-use.sh"}]}]
HOOKEOF
  jq --slurpfile hook "$POST_HOOK_TMP" '.hooks.PostToolUse = $hook[0]' \
    "$CODEX_HOOKS" > "$CODEX_HOOKS.tmp" && mv "$CODEX_HOOKS.tmp" "$CODEX_HOOKS"
  rm -f "$POST_HOOK_TMP"
  echo "[x] Codex PostToolUse hook registered"
fi
```

- [ ] **Step 5: Update SessionStart hook to use ORCA_ROLE**

Replace the hardcoded role messages:

```bash
# Claude Code SessionStart hook — role-aware
CLAUDE_HOOK_TMP=$(mktemp)
cat > "$CLAUDE_HOOK_TMP" << 'HOOKEOF'
[{"hooks":[{"type":"command","command":"if [ -n \"$ORCA\" ]; then echo \"Orca active. Role: ${ORCA_ROLE:-unknown}. Run /orca\"; fi"}]}]
HOOKEOF
```

- [ ] **Step 6: shellcheck + commit**

Run: `shellcheck install.sh`

```bash
git add install.sh
git commit -m "feat: install.sh register orca-worktree, heartbeat hooks, role-aware SessionStart"
```

---

### Task 6: skills/orca/SKILL.md — multi-worker update

**Files:**
- Modify: `skills/orca/SKILL.md`

- [ ] **Step 1: Rewrite SKILL.md for multi-worker**

```markdown
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

## Communication

One command, always chain with `&&`:

\`\`\`bash
tmux-bridge read $ORCA_PEER 5 && tmux-bridge message $ORCA_PEER "msg" && tmux-bridge read $ORCA_PEER 5 && tmux-bridge keys $ORCA_PEER Enter
\`\`\`

Read Guard: must `read` before every `type`/`keys`.

Multi-worker: use specific label from `$ORCA_WORKERS` instead of `$ORCA_PEER`.

## Lead

1. **Confirm** — discuss breakdown with user before dispatching
2. **Dispatch** — for each worker, send: goal, scope, constraints, worktree path. End with: "Run /review, build, test. Fix issues, then report."
   - Single worker: use `$ORCA_PEER`
   - Multi-worker: iterate `$ORCA_WORKERS` (comma-separated), dispatch to each
   - Worktree: run `orca-worktree create <id>` first, tell worker to `cd` into it
3. **Wait** — say "dispatched, waiting" and **end turn**. Do not poll.
   - Heartbeat: `[orca]` notifications appear automatically via PreToolUse hook
4. **Optimize** — on report, /simplify changed files
5. **Report** — summarize to user

## Worker

1. **Wait** — reply "Worker ready." and end turn
2. **Implement** -> **Self-review** (/review, fix, repeat) -> **Test** (build + tests)
3. **Report** — 1-2 sentence summary to lead, no code/diffs

Workers can also initiate: ask lead for help or confirm approach.

## Rules

1. Read before type/keys
2. One `&&` chain per communication
3. No polling — heartbeat handles idle detection
```

- [ ] **Step 2: Commit**

```bash
git add skills/orca/SKILL.md
git commit -m "feat: SKILL.md multi-worker support with env vars and heartbeat"
```

---

### Task 7: Docs + PLAN.md update

**Files:**
- Modify: `PLAN.md`
- Modify: `docs/ARCHITECTURE.md`

- [ ] **Step 1: Update PLAN.md checkboxes**

Mark P0 items as completed.

- [ ] **Step 2: Update ARCHITECTURE.md**

Add new decisions:
- Role from env var (`$ORCA_ROLE`) not activation command
- Heartbeat via hooks (PostToolUse write, PreToolUse check) — no background monitor needed
- Worktree at `.orca/worktree/<id>` via `orca-worktree.sh`

- [ ] **Step 3: Commit**

```bash
git add PLAN.md docs/ARCHITECTURE.md
git commit -m "docs: update PLAN.md and ARCHITECTURE.md for P0 completion"
```
