#!/usr/bin/env bash
set -euo pipefail

SESSION="orca-$(basename "$(pwd)")"
# Per-instance dedicated tmux server (D8): isolates orca from the user's main
# tmux server so stop=kill-server gives a clean env on next start, and orca
# never pollutes / inherits stale env from the user's long-lived server.
SOCKET="$SESSION"
TMUX_CMD="tmux -L $SOCKET"
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
if $TMUX_CMD has-session -t "$SESSION" 2>/dev/null; then
  $TMUX_CMD attach -t "$SESSION"
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
$TMUX_CMD new-session -d -s "$SESSION" -n main -c "$WORKDIR"

# Split worker pane (right, 50% width)
$TMUX_CMD split-window -h -t "$SESSION:main" -c "$WORKDIR"

# --- Even layout ---
$TMUX_CMD select-layout -t "$SESSION:main" even-horizontal

# --- tmux config ---
$TMUX_CMD set-option -t "$SESSION" mode-keys vi
$TMUX_CMD set-option -t "$SESSION" mouse on
$TMUX_CMD bind-key Space select-layout even-horizontal
# Pass through Kitty keyboard protocol (Ghostty/WezTerm/Kitty) so inner CLIs
# can negotiate Shift+Enter etc. Without this tmux strips the modifiers.
$TMUX_CMD set-option -gs extended-keys on
# Idempotent append: tmux's -ga doesn't dedupe; multiple orca starts would
# pile up duplicate entries.
if ! $TMUX_CMD show-options -gs terminal-features 2>/dev/null | grep -q ':extkeys'; then
  $TMUX_CMD set-option -ga terminal-features ',*:extkeys'
fi

# --- Name panes (session-prefixed for multi-instance isolation) ---
LEAD_LABEL="${SESSION}-lead"
CODER_LABEL="${SESSION}-coder"
# tmux-bridge auto-detects the socket via $TMUX inside panes, but `name` is
# called from this script (outside any pane), so pass socket explicitly.
# Ask tmux for its actual socket path (portable across macOS / Linux).
SOCKET_PATH=$($TMUX_CMD display-message -p -t "$SESSION" '#{socket_path}')
TMUX_BRIDGE_SOCKET="$SOCKET_PATH" tmux-bridge name "$SESSION:main.0" "$LEAD_LABEL"
TMUX_BRIDGE_SOCKET="$SOCKET_PATH" tmux-bridge name "$SESSION:main.1" "$CODER_LABEL"

# --- Inject env ---
$TMUX_CMD send-keys -t "$SESSION:main.0" "export ORCA=1 ORCA_PEER=$CODER_LABEL" Enter
$TMUX_CMD send-keys -t "$SESSION:main.1" "export ORCA=1 ORCA_PEER=$LEAD_LABEL" Enter

# --- Launch agents ---
$TMUX_CMD send-keys -t "$SESSION:main.0" "claude" Enter
# Codex: pass $orca as initial prompt to auto-activate skill
$TMUX_CMD send-keys -t "$SESSION:main.1" "$CODER_CMD '\$orca'" Enter

# --- /clear re-activation monitor ---
# After Codex /clear, monitor detects welcome screen and inputs $orca
# User must press Enter manually (tmux can't send Enter to Codex ratatui TUI)
_skill_monitor() {
  set +e
  local session="$1" pane="$2"
  while $TMUX_CMD has-session -t "$session" 2>/dev/null; do
    local out banner
    out=$($TMUX_CMD capture-pane -p -t "$pane" 2>/dev/null \
      | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g') || true
    banner=$(echo "$out" | grep -c '>_ OpenAI Codex')
    if [ "$banner" -gt 0 ] && ! echo "$out" | grep -q '\$orca'; then
      sleep 2
      $TMUX_CMD send-keys -l -t "$pane" '$orca'
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
$TMUX_CMD select-pane -t "$SESSION:main.0"

# --- Attach ---
$TMUX_CMD attach -t "$SESSION"
