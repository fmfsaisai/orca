#!/usr/bin/env bash
set -euo pipefail

SESSION="orch-$(basename "$(pwd)")"
CODER_BIN="${1:-codex}"
CODER_ARGS="--sandbox danger-full-access -a on-request -c features.codex_hooks=true"
CODER_CMD="$CODER_BIN $CODER_ARGS"

# --- 前置检查 ---
if ! command -v tmux &>/dev/null; then
  echo "错误: tmux 未安装。请先 brew install tmux" >&2
  exit 1
fi

if ! command -v tmux-bridge &>/dev/null; then
  echo "错误: smux 未安装。请先运行:" >&2
  echo "  curl -fsSL https://shawnpana.com/smux/install.sh | bash" >&2
  exit 1
fi

if ! command -v "$CODER_BIN" &>/dev/null; then
  echo "错误: $CODER_BIN 未安装" >&2
  exit 1
fi

# --- 检查是否已存在 ---
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux attach -t "$SESSION"
  exit 0
fi

# --- 获取工作目录 ---
WORKDIR="${ORCHESTRA_WORKDIR:-$(pwd)}"

# --- 创建 session ---
echo "启动 $SESSION ..."
echo "  Lead:   claude"
echo "  Coder:  $CODER_CMD"
echo "  工作目录: $WORKDIR"

# 创建 session，左侧 Lead
tmux new-session -d -s "$SESSION" -n main -c "$WORKDIR"

# 右侧分出 Coder pane (50% 宽度)
tmux split-window -h -t "$SESSION:main" -c "$WORKDIR"

# --- 均分布局 ---
tmux select-layout -t "$SESSION:main" even-horizontal

# --- 命名 pane（带 session 前缀，隔离多实例） ---
LEAD_LABEL="${SESSION}-lead"
CODER_LABEL="${SESSION}-coder"
tmux-bridge name "$SESSION:main.0" "$LEAD_LABEL"
tmux-bridge name "$SESSION:main.1" "$CODER_LABEL"

# --- 注入环境标记 ---
tmux send-keys -t "$SESSION:main.0" "export ORCH=1 ORCH_PEER=$CODER_LABEL" Enter
tmux send-keys -t "$SESSION:main.1" "export ORCH=1 ORCH_PEER=$LEAD_LABEL" Enter

# --- 启动 agents ---
tmux send-keys -t "$SESSION:main.0" "claude" Enter
# Codex 启动时直接传 $orchestra 作为首条 prompt，自动激活 skill（无需 monitor/send-keys）
tmux send-keys -t "$SESSION:main.1" "$CODER_CMD '\$orchestra'" Enter

# --- /clear 后的 skill 重新激活（monitor） ---
# Codex /clear 后会出现新的欢迎界面，monitor 检测到后输入 $orchestra
# 因为 tmux 无法向 Codex TUI 发送 Enter，需要用户手动按 Enter 确认
_skill_monitor() {
  set +e
  local session="$1" pane="$2" last_banner=""
  while tmux has-session -t "$session" 2>/dev/null; do
    local out banner
    out=$(tmux capture-pane -p -t "$pane" 2>/dev/null \
      | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g') || true
    # 检测 Codex 欢迎界面（启动和 /clear 后都会出现）
    banner=$(echo "$out" | grep -c '>_ OpenAI Codex')
    # 欢迎界面可见 + 输入区没有 $orchestra → 发送
    if [ "$banner" -gt 0 ] && ! echo "$out" | grep -q '\$orchestra'; then
      sleep 2
      tmux send-keys -l -t "$pane" '$orchestra'
    fi
    sleep 3
  done
}

# 杀掉旧 monitor
MONITOR_PID="/tmp/orch-monitor-${SESSION}.pid"
if [ -f "$MONITOR_PID" ]; then
  kill "$(cat "$MONITOR_PID")" 2>/dev/null || true
  rm -f "$MONITOR_PID"
fi

_skill_monitor "$SESSION" "$SESSION:main.1" &
echo $! > "$MONITOR_PID"

# --- 聚焦到 Lead pane ---
tmux select-pane -t "$SESSION:main.0"

# --- 直接 attach ---
tmux attach -t "$SESSION"
