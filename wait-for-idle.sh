#!/usr/bin/env bash
set -euo pipefail

# Wait for an AI agent in a tmux pane to become idle (detect prompt).
# Usage: ./wait-for-idle.sh -t <target> [-T timeout] [-i interval] [-l lines]
#
# Examples:
#   ./wait-for-idle.sh -t coder              # Wait for coder, 300s timeout
#   ./wait-for-idle.sh -t coder -T 600       # 10 minute timeout
#   ./wait-for-idle.sh -t coder -i 1         # 1 second poll interval

TARGET=""
TIMEOUT=300
INTERVAL=0.5
LINES=5
STABLE=3  # consecutive idle detections required

usage() {
  echo "Usage: $0 -t <target> [-T timeout] [-i interval] [-l lines]"
  echo "  -t  tmux target (pane label or session:window.pane)"
  echo "  -T  timeout seconds (default: 300)"
  echo "  -i  poll interval seconds (default: 0.5)"
  echo "  -l  lines to check (default: 5)"
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
  echo "Error: -t <target> required" >&2
  usage
fi

# Resolve label to tmux target if needed
if [[ "$TARGET" != *:* && "$TARGET" != *.* ]]; then
  if command -v tmux-bridge &>/dev/null; then
    RESOLVED=$(tmux-bridge resolve "$TARGET" 2>/dev/null || echo "")
    if [[ -n "$RESOLVED" ]]; then
      TARGET="$RESOLVED"
    fi
  fi
fi

# Idle prompt patterns for Claude Code and Codex CLI
IDLE_PATTERN='^[[:space:]]*(>|❯|›)[[:space:]]|^[[:space:]]*codex>[[:space:]]*$|Find and fix a bug'

strip_ansi() {
  perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g; s/\e\([0-9;]*[a-zA-Z]//g'
}

deadline=$(($(date +%s) + TIMEOUT))
idle_count=0

while true; do
  pane_text=$(tmux capture-pane -p -J -t "$TARGET" -S "-${LINES}" 2>/dev/null || echo "")

  cleaned=$(echo "$pane_text" | strip_ansi)
  if echo "$cleaned" | grep -qE "$IDLE_PATTERN"; then
    idle_count=$((idle_count + 1))
    if (( idle_count >= STABLE )); then
      exit 0
    fi
  else
    idle_count=0
  fi

  now=$(date +%s)
  if (( now >= deadline )); then
    echo "Timeout (${TIMEOUT}s), last output:" >&2
    echo "$pane_text" | strip_ansi >&2
    exit 1
  fi

  sleep "$INTERVAL"
done
