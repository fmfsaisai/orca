#!/usr/bin/env bash
set -euo pipefail

SESSION="orca-$(basename "$(pwd)")"
# Per-instance dedicated tmux server (D8): the server only owns this one
# session, so killing the server is equivalent to killing the session and
# also wipes the cached global env that would otherwise leak into the next
# `orca` start. See docs/troubleshooting/tmux-server-stale-env.md.
SOCKET="$SESSION"
TMUX_CMD="tmux -L $SOCKET"

if ! $TMUX_CMD has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' does not exist"
  exit 0
fi

echo "Panes in $SESSION:"
$TMUX_CMD list-panes -t "$SESSION" -F "  #{pane_index}: #{pane_current_command} (pid: #{pane_pid})"

echo ""
read -rp "Stop $SESSION? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Cancelled"
  exit 0
fi

MONITOR_PID="/tmp/orca-monitor-${SESSION}.pid"
if [ -f "$MONITOR_PID" ]; then
  kill "$(cat "$MONITOR_PID")" 2>/dev/null || true
  rm -f "$MONITOR_PID"
fi

# Kill the dedicated server (not just the session). This is what gives the
# next `orca` start a clean env — the server holds the cached -g environment.
$TMUX_CMD kill-server 2>/dev/null || true
echo "Stopped $SESSION (server killed, env cleared)"
