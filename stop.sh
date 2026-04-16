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

MONITOR_PID="/tmp/orca-monitor-${SESSION}.pid"
if [ -f "$MONITOR_PID" ]; then
  kill "$(cat "$MONITOR_PID")" 2>/dev/null || true
  rm -f "$MONITOR_PID"
fi

tmux kill-session -t "$SESSION"
echo "Stopped $SESSION"
