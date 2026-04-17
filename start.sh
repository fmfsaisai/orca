#!/usr/bin/env bash
set -euo pipefail

SESSION="orca-$(basename "$(pwd)")"
CODER_BIN="${1:-codex}"
CODER_ARGS="--sandbox danger-full-access -a on-request -c features.codex_hooks=true"
CODER_CMD="$CODER_BIN $CODER_ARGS"

# --- Prerequisites ---
if ! command -v tmux &>/dev/null; then
  echo "Error: tmux not installed. Run: brew install tmux" >&2
  exit 1
fi

if ! command -v tmux-bridge &>/dev/null; then
  echo "Error: smux not installed. Run:" >&2
  echo "  curl -fsSL https://shawnpana.com/smux/install.sh | bash" >&2
  exit 1
fi

if ! command -v "$CODER_BIN" &>/dev/null; then
  echo "Error: $CODER_BIN not installed" >&2
  exit 1
fi

# --- Reattach if exists ---
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux attach -t "$SESSION"
  exit 0
fi

# --- Working directory ---
WORKDIR="${ORCA_WORKDIR:-$(pwd)}"

# --- Create session ---
echo "Starting $SESSION ..."
echo "  Lead:   claude"
echo "  Worker: $CODER_CMD"
echo "  Dir:    $WORKDIR"

# Create session with lead pane (left)
tmux new-session -d -s "$SESSION" -n main -c "$WORKDIR"

# Split worker pane (right, 50% width)
tmux split-window -h -t "$SESSION:main" -c "$WORKDIR"

# --- Even layout ---
tmux select-layout -t "$SESSION:main" even-horizontal

# --- tmux config ---
tmux set-option -t "$SESSION" mode-keys vi
tmux set-option -t "$SESSION" mouse on
tmux bind-key Space select-layout even-horizontal
# Pass through Kitty keyboard protocol (Ghostty/WezTerm/Kitty) so inner CLIs
# can negotiate Shift+Enter etc. Without this tmux strips the modifiers.
tmux set-option -gs extended-keys on
tmux set-option -ga terminal-features ',*:extkeys'

# --- Name panes (session-prefixed for multi-instance isolation) ---
LEAD_LABEL="${SESSION}-lead"
CODER_LABEL="${SESSION}-coder"
tmux-bridge name "$SESSION:main.0" "$LEAD_LABEL"
tmux-bridge name "$SESSION:main.1" "$CODER_LABEL"

# --- Inject env ---
tmux send-keys -t "$SESSION:main.0" "export ORCA=1 ORCA_PEER=$CODER_LABEL" Enter
tmux send-keys -t "$SESSION:main.1" "export ORCA=1 ORCA_PEER=$LEAD_LABEL" Enter

# --- Launch agents ---
tmux send-keys -t "$SESSION:main.0" "claude" Enter
# Codex: pass $orca as initial prompt to auto-activate skill
tmux send-keys -t "$SESSION:main.1" "$CODER_CMD '\$orca'" Enter

# --- /clear re-activation monitor ---
# After Codex /clear, monitor detects welcome screen and inputs $orca
# User must press Enter manually (tmux can't send Enter to Codex ratatui TUI)
_skill_monitor() {
  set +e
  local session="$1" pane="$2"
  while tmux has-session -t "$session" 2>/dev/null; do
    local out banner
    out=$(tmux capture-pane -p -t "$pane" 2>/dev/null \
      | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g') || true
    banner=$(echo "$out" | grep -c '>_ OpenAI Codex')
    if [ "$banner" -gt 0 ] && ! echo "$out" | grep -q '\$orca'; then
      sleep 2
      tmux send-keys -l -t "$pane" '$orca'
    fi
    sleep 3
  done
}

# Kill old monitor
MONITOR_PID="/tmp/orca-monitor-${SESSION}.pid"
if [ -f "$MONITOR_PID" ]; then
  kill "$(cat "$MONITOR_PID")" 2>/dev/null || true
  rm -f "$MONITOR_PID"
fi

_skill_monitor "$SESSION" "$SESSION:main.1" &
echo $! > "$MONITOR_PID"

# --- Focus lead pane ---
tmux select-pane -t "$SESSION:main.0"

# --- Attach ---
tmux attach -t "$SESSION"
