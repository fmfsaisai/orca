#!/usr/bin/env bash
set -euo pipefail

SESSION="orca-$(basename "$(pwd)")"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "session '$SESSION' 不存在，无需清理"
  exit 0
fi

# 显示当前 pane 状态
echo "当前 $SESSION session 中的 pane:"
tmux list-panes -t "$SESSION" -F "  #{pane_index}: #{pane_current_command} (pid: #{pane_pid})"

echo ""
read -rp "确认停止 $SESSION session? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "取消"
  exit 0
fi

MONITOR_PID="/tmp/orca-monitor-${SESSION}.pid"
if [ -f "$MONITOR_PID" ]; then
  kill "$(cat "$MONITOR_PID")" 2>/dev/null || true
  rm -f "$MONITOR_PID"
fi

tmux kill-session -t "$SESSION"
echo "已停止 $SESSION session"
