#!/usr/bin/env bash
set -euo pipefail

# 等待 tmux pane 中的 AI agent 进入 idle 状态（检测提示符）
# 用法: ./wait-for-idle.sh -t <target> [-T timeout] [-i interval] [-l lines]
#
# 示例:
#   ./wait-for-idle.sh -t coder              # 等待 coder 完成，默认 300s 超时
#   ./wait-for-idle.sh -t reviewer -T 600    # 等待 reviewer，10 分钟超时
#   ./wait-for-idle.sh -t coder -i 1         # 1 秒轮询间隔

TARGET=""
TIMEOUT=300
INTERVAL=0.5
LINES=5
STABLE=3  # 连续 N 次检测到 idle 才确认，避免瞬间空闲误判

usage() {
  echo "用法: $0 -t <target> [-T timeout] [-i interval] [-l lines]"
  echo "  -t  tmux target (pane label 或 session:window.pane)"
  echo "  -T  超时秒数 (默认: 300)"
  echo "  -i  轮询间隔秒数 (默认: 0.5)"
  echo "  -l  检查最后几行 (默认: 5)"
  exit 1
}

while getopts "t:T:i:l:h" opt; do
  case $opt in
    t) TARGET="$OPTARG" ;;
    T) TIMEOUT="$OPTARG" ;;
    i) INTERVAL="$OPTARG" ;;
    l) LINES="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "错误: 必须指定 -t <target>" >&2
  usage
fi

# 如果 target 是 label（不含 : 或 .），尝试用 tmux-bridge resolve
if [[ "$TARGET" != *:* && "$TARGET" != *.* ]]; then
  if command -v tmux-bridge &>/dev/null; then
    RESOLVED=$(tmux-bridge resolve "$TARGET" 2>/dev/null || echo "")
    if [[ -n "$RESOLVED" ]]; then
      TARGET="$RESOLVED"
    fi
  fi
fi

# Claude Code 和 Codex CLI 的 idle 提示符模式
# Claude Code: 行首 > 或 ❯ 后跟空格
# Codex CLI: "› Find and fix a bug" 或行首 ❯/› 或 codex>
IDLE_PATTERN='^[[:space:]]*(>|❯|›)[[:space:]]|^[[:space:]]*codex>[[:space:]]*$|Find and fix a bug'

# ANSI 转义码清理 (macOS BSD sed 兼容)
strip_ansi() {
  perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g; s/\e\([0-9;]*[a-zA-Z]//g'
}

deadline=$(($(date +%s) + TIMEOUT))
idle_count=0

while true; do
  # 截取 pane 最后 N 行
  pane_text=$(tmux capture-pane -p -J -t "$TARGET" -S "-${LINES}" 2>/dev/null || echo "")

  # 清理 ANSI 码后检测提示符
  cleaned=$(echo "$pane_text" | strip_ansi)
  if echo "$cleaned" | grep -qE "$IDLE_PATTERN"; then
    idle_count=$((idle_count + 1))
    if (( idle_count >= STABLE )); then
      exit 0
    fi
  else
    idle_count=0
  fi

  # 检查超时
  now=$(date +%s)
  if (( now >= deadline )); then
    echo "超时 (${TIMEOUT}s)，最后输出:" >&2
    echo "$pane_text" | strip_ansi >&2
    exit 1
  fi

  sleep "$INTERVAL"
done
