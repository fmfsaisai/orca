#!/usr/bin/env bash
set -euo pipefail

SESSION="orch-$(basename "$(pwd)")"
CODER_BIN="${1:-codex}"
CODER_ARGS="--sandbox danger-full-access -a on-request"
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

# --- 命名 pane ---
tmux-bridge name "$SESSION:main.0" lead
tmux-bridge name "$SESSION:main.1" coder

# --- 注入角色 ---
tmux send-keys -t "$SESSION:main.0" "export ORCH_ROLE=lead" Enter
tmux send-keys -t "$SESSION:main.1" "export ORCH_ROLE=coder" Enter

# --- 启动 agents ---
tmux send-keys -t "$SESSION:main.0" "claude" Enter
tmux send-keys -t "$SESSION:main.1" "$CODER_CMD" Enter

# --- 等待 agent 启动就绪后自动初始化 ---
sleep 3
tmux send-keys -t "$SESSION:main.0" "echo \$ORCH_ROLE" Enter
sleep 5
tmux send-keys -t "$SESSION:main.1" "你的角色是 coder (ORCH_ROLE=coder)" Enter

# --- 聚焦到 Lead pane ---
tmux select-pane -t "$SESSION:main.0"

# --- 直接 attach ---
tmux attach -t "$SESSION"
