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
tmux send-keys -t "$SESSION:main.1" "$CODER_CMD" Enter

# --- Codex 自动填入 skill 命令（用户手动回车确认） ---
_wait_and_prefill() {
  local pane="$1" cmd="$2" output
  for i in $(seq 1 30); do
    sleep 2
    output=$(tmux capture-pane -p -t "$pane" 2>/dev/null \
      | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g') || true
    if echo "$output" | grep -qE '^[[:space:]]*(>|❯|›)[[:space:]]|Find and fix a bug'; then
      sleep 1
      tmux send-keys -l -t "$pane" "$cmd"
      return 0
    fi
  done
}

_wait_and_prefill "$SESSION:main.1" '$orchestra' &

# --- 聚焦到 Lead pane ---
tmux select-pane -t "$SESSION:main.0"

# --- 直接 attach ---
tmux attach -t "$SESSION"
