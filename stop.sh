#!/usr/bin/env bash
set -euo pipefail

# Sanitize basename: tmux uses `.` and `:` as target separators
# (session:window.pane), so dirs containing them break tmux targeting.
SESSION="orca-$(basename "$(pwd)" | tr '.:' '--')"
# Per-instance dedicated tmux server (D8): the server only owns this one
# session, so killing the server is equivalent to killing the session and
# also wipes the cached global env that would otherwise leak into the next
# `orca` start. See docs/troubleshooting/tmux-server-stale-env.md.
SOCKET="$SESSION"
TMUX_CMD="tmux -L $SOCKET"

# Detect both targets:
#   - dedicated: session on per-instance server (D8, current scheme)
#   - legacy:   session on user's main tmux server (pre-D8 orphans, since
#               nothing else can manage them after the upgrade)
HAS_DEDICATED=false
HAS_LEGACY=false

if $TMUX_CMD has-session -t "$SESSION" 2>/dev/null; then
  HAS_DEDICATED=true
fi
if tmux has-session -t "$SESSION" 2>/dev/null; then
  HAS_LEGACY=true
fi

if ! $HAS_DEDICATED && ! $HAS_LEGACY; then
  echo "Session '$SESSION' does not exist (neither dedicated nor legacy)"
  exit 0
fi

echo "Found:"
if $HAS_DEDICATED; then
  echo "  - dedicated server: $SESSION"
  $TMUX_CMD list-panes -t "$SESSION" -F "      pane #{pane_index}: #{pane_current_command} (pid: #{pane_pid})"
fi
if $HAS_LEGACY; then
  echo "  - main tmux (legacy, pre-D8): $SESSION"
  tmux list-panes -t "$SESSION" -F "      pane #{pane_index}: #{pane_current_command} (pid: #{pane_pid})"
fi

echo ""
read -rp "Stop all of the above? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Cancelled"
  exit 0
fi

# Kill all monitor processes for this session
for pid_file in /tmp/orca-monitor-"${SESSION}"-*.pid; do
  [ -f "$pid_file" ] || continue
  kill "$(cat "$pid_file")" 2>/dev/null || true
  rm -f "$pid_file"
done
# Legacy single-pid monitor (pre-multi-worker)
MONITOR_PID="/tmp/orca-monitor-${SESSION}.pid"
if [ -f "$MONITOR_PID" ]; then
  kill "$(cat "$MONITOR_PID")" 2>/dev/null || true
  rm -f "$MONITOR_PID"
fi

# Clean up worktrees
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/orca-worktree.sh" ]; then
  "$SCRIPT_DIR/orca-worktree.sh" clean 2>/dev/null || true
fi

# Clean up heartbeat state
rm -rf .orca/heartbeat 2>/dev/null || true

if $HAS_DEDICATED; then
  # Kill the dedicated server (not just the session). This is what gives the
  # next `orca` start a clean env — the server holds the cached -g environment.
  $TMUX_CMD kill-server 2>/dev/null || true
  echo "Stopped dedicated server for $SESSION (server killed, env cleared)"
fi

if $HAS_LEGACY; then
  # Just kill the session, not the user's main tmux server (which may host
  # other unrelated sessions).
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  echo "Cleaned up legacy $SESSION on main tmux server"
fi
