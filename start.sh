#!/usr/bin/env bash
set -euo pipefail

# Subcommand dispatcher. start.sh is the single entry point installed as
# `orca`; named subcommands route to sibling scripts, anything else falls
# through to the start logic below.
# Resolve symlinks portably (macOS BSD readlink has no -f) so dispatch works
# when invoked via ~/.local/bin/orca → /path/to/repo/start.sh.
_orca_src="${BASH_SOURCE[0]}"
while [ -L "$_orca_src" ]; do
  _orca_dir="$(cd -P "$(dirname "$_orca_src")" && pwd)"
  _orca_src="$(readlink "$_orca_src")"
  [[ "$_orca_src" != /* ]] && _orca_src="$_orca_dir/$_orca_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_orca_src")" && pwd)"
unset _orca_src _orca_dir
case "${1:-}" in
  stop)  shift; exec "$SCRIPT_DIR/stop.sh"          "$@" ;;
  idle)  shift; exec "$SCRIPT_DIR/wait-for-idle.sh" "$@" ;;
  ps)    shift; exec "$SCRIPT_DIR/ps.sh"            "$@" ;;
  rm)    shift; exec "$SCRIPT_DIR/rm.sh"            "$@" ;;
  prune) shift; exec "$SCRIPT_DIR/prune.sh"         "$@" ;;
  ""|-*) ;;  # no arg or flags → fall through to start logic
  *)
    echo "Error: unknown command '$1'" >&2
    echo "Usage: orca [stop|idle|ps|rm|prune] [--workers N] [--lead MODEL] [--worker MODEL] [--workflow NAME]" >&2
    exit 1
    ;;
esac

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# --- Defaults ---
CODEX_DEFAULT_CMD="codex --sandbox danger-full-access -a on-request -c features.codex_hooks=true"
WORKERS=1
LEAD_MODEL="claude"
WORKER_MODEL="codex"
WORKFLOW=""
START_ARGS_PASSED=false

# --- Usage ---
usage() {
  cat <<EOF
Usage: orca [COMMAND] [OPTIONS]

Commands:
  stop          Stop current instance
  idle          Wait for idle
  ps            List instances
  rm <name|id>  Remove instance
  prune         Clean dead sockets

Start options:
  -n, --workers N      Number of workers (default: 1)
      --lead MODEL     Lead model: claude|codex|<binary> (default: claude)
      --worker MODEL   Worker model: claude|codex|<binary> (default: codex)
  -w, --workflow NAME  Workflow skill (sets ORCA_WORKFLOW)
  -h, --help           Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--workers)  WORKERS="${2:?--workers requires a value}"; START_ARGS_PASSED=true; shift 2 ;;
    --lead)        LEAD_MODEL="${2:?--lead requires a value}"; START_ARGS_PASSED=true; shift 2 ;;
    --worker)      WORKER_MODEL="${2:?--worker requires a value}"; START_ARGS_PASSED=true; shift 2 ;;
    -w|--workflow) WORKFLOW="${2:?--workflow requires a value}"; START_ARGS_PASSED=true; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# --- Model command mapping ---
model_cmd() {
  case "$1" in
    claude) echo "claude" ;;
    codex)  echo "$CODEX_DEFAULT_CMD" ;;
    *)      echo "$1" ;;
  esac
}

model_bin() {
  local cmd; cmd="$(model_cmd "$1")"
  echo "${cmd%% *}"
}

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

LEAD_BIN="$(model_bin "$LEAD_MODEL")"
if ! command -v "$LEAD_BIN" &>/dev/null; then
  echo "Error: lead binary '$LEAD_BIN' not found" >&2
  exit 1
fi

WORKER_BIN="$(model_bin "$WORKER_MODEL")"
if ! command -v "$WORKER_BIN" &>/dev/null; then
  echo "Error: worker binary '$WORKER_BIN' not found" >&2
  exit 1
fi

# --- Working directory ---
WORKDIR="${ORCA_WORKDIR:-$(pwd)}"

# --- Existing instances in this cwd ---
existing=()
while IFS= read -r row; do
  [ -n "$row" ] || continue
  existing+=("$row")
done < <(list_instances_in_cwd "$WORKDIR" | sort -t '|' -k4,4nr)

if [ "${#existing[@]}" -gt 0 ]; then
  picker_rows=()
  for row in "${existing[@]}"; do
    IFS='|' read -r _socket_name session_name attached created panes <<<"$row"
    status=$([ "$attached" = "1" ] && echo "attached" || echo "detached")
    picker_rows+=("$(format_picker_row "$session_name" "$status" "$panes" "$(format_uptime "$created")")")
  done

  if ! pick="$(pick_one_tui \
    "Resume an orca in $(shorten_path "$WORKDIR"), or start a new one?" \
    "" \
    "start a new one" \
    "${picker_rows[@]}")"; then
    echo "Cancelled"
    exit 0
  fi

  if [ "$pick" != "NEW" ]; then
    chosen="${existing[$((pick - 1))]}"
    IFS='|' read -r socket_name session_name _attached _created _panes <<<"$chosen"
    if $START_ARGS_PASSED; then
      echo "Warning: start args are ignored when attaching to an existing instance"
    fi
    exec tmux -L "$socket_name" attach -t "$session_name"
  fi
fi

SESSION="$(next_session_name "$WORKDIR")"
# Per-instance dedicated tmux server: isolates orca from the user's main
# tmux server so stop=kill-server gives a clean env on next start, and orca
# never pollutes / inherits stale env from the user's long-lived server.
SOCKET="$SESSION"
TMUX_CMD="tmux -L $SOCKET"

# --- Build worker labels (space-separated, bash 3.2 compat) ---
WORKER_LABELS=""
i=1
while [ "$i" -le "$WORKERS" ]; do
  label="${SESSION}-worker-${i}"
  WORKER_LABELS="${WORKER_LABELS}${WORKER_LABELS:+ }${label}"
  i=$((i + 1))
done
WORKERS_CSV="$(echo "$WORKER_LABELS" | tr ' ' ',')"
FIRST_WORKER_LABEL="${WORKER_LABELS%% *}"

# --- Startup info ---
echo "Starting $SESSION ..."
echo "  Lead:    $LEAD_MODEL ($(model_cmd "$LEAD_MODEL"))"
echo "  Worker:  $WORKER_MODEL ($(model_cmd "$WORKER_MODEL"))"
echo "  Workers: $WORKERS"
echo "  Dir:     $WORKDIR"
[ -n "$WORKFLOW" ] && echo "  Workflow: $WORKFLOW"

# --- Create session with lead pane (left) ---
$TMUX_CMD new-session -d -s "$SESSION" -n main -c "$WORKDIR"

# --- Create worker panes ---
i=1
while [ "$i" -le "$WORKERS" ]; do
  $TMUX_CMD split-window -h -t "$SESSION:main" -c "$WORKDIR"
  i=$((i + 1))
done

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
# Pass through OSC 8 hyperlinks so terminals (Ghostty/Zed/iTerm2) can cmd+click
# link text emitted by inner CLIs (e.g. Claude Code). Without this tmux strips
# the escape sequence and only the plain text reaches the outer terminal.
if ! $TMUX_CMD show-options -gs terminal-features 2>/dev/null | grep -q ':hyperlinks'; then
  $TMUX_CMD set-option -ga terminal-features ',*:hyperlinks'
fi

# --- Name panes (session-prefixed for multi-instance isolation) ---
# tmux-bridge auto-detects the socket via $TMUX inside panes, but `name` is
# called from this script (outside any pane), so pass socket explicitly.
SOCKET_PATH=$($TMUX_CMD display-message -p -t "$SESSION" '#{socket_path}')
LEAD_LABEL="${SESSION}-lead"
TMUX_BRIDGE_SOCKET="$SOCKET_PATH" tmux-bridge name "$SESSION:main.0" "$LEAD_LABEL"
i=1
for label in $WORKER_LABELS; do
  TMUX_BRIDGE_SOCKET="$SOCKET_PATH" tmux-bridge name "$SESSION:main.${i}" "$label"
  i=$((i + 1))
done

# --- Launch agent helper ---
launch_agent() {
  local pane="$1" model="$2" role="$3"
  local cmd; cmd="$(model_cmd "$model")"
  local bin="${cmd%% *}"
  if [ "$bin" = "codex" ]; then
    if [ "$role" = "worker" ]; then
      $TMUX_CMD send-keys -t "$pane" "$cmd '\$orca'" Enter
    else
      $TMUX_CMD send-keys -t "$pane" "$cmd '/orca'" Enter
    fi
  else
    $TMUX_CMD send-keys -t "$pane" "$cmd" Enter
  fi
}

# --- Inject env + launch workers ---
i=1
for label in $WORKER_LABELS; do
  pane="$SESSION:main.${i}"
  env_cmd="export ORCA=1 ORCA_ROLE=worker ORCA_PEER=${LEAD_LABEL} ORCA_WORKER_ID=${i} ORCA_ROOT=${WORKDIR} ORCA_SESSION=${SESSION}"
  [ -n "$WORKFLOW" ] && env_cmd="${env_cmd} ORCA_WORKFLOW=${WORKFLOW}"
  $TMUX_CMD send-keys -t "$pane" "$env_cmd" Enter
  launch_agent "$pane" "$WORKER_MODEL" "worker"
  i=$((i + 1))
done

# --- Inject env + launch lead ---
lead_env="export ORCA=1 ORCA_ROLE=lead ORCA_WORKERS=${WORKERS_CSV} ORCA_PEER=${FIRST_WORKER_LABEL} ORCA_ROOT=${WORKDIR} ORCA_SESSION=${SESSION}"
[ -n "$WORKFLOW" ] && lead_env="${lead_env} ORCA_WORKFLOW=${WORKFLOW}"
$TMUX_CMD send-keys -t "$SESSION:main.0" "$lead_env" Enter
launch_agent "$SESSION:main.0" "$LEAD_MODEL" "lead"

# --- /clear re-activation monitor ---
# After Codex /clear, monitor detects welcome screen and inputs the skill cmd.
# User must press Enter manually (tmux can't send Enter to Codex ratatui TUI).
_skill_monitor() {
  set +e
  local session="$1" pane="$2" role="$3"
  local skill_cmd
  if [ "$role" = "worker" ]; then
    # shellcheck disable=SC2016  # $orca is a literal codex skill command, not a variable
    skill_cmd='$orca'
  else
    skill_cmd='/orca'
  fi
  while $TMUX_CMD has-session -t "$session" 2>/dev/null; do
    local out banner
    out=$($TMUX_CMD capture-pane -p -t "$pane" 2>/dev/null \
      | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g') || true
    banner=$(echo "$out" | grep -c '>_ OpenAI Codex' || true)
    if [ "$banner" -gt 0 ] && ! echo "$out" | grep -q "$skill_cmd"; then
      sleep 2
      $TMUX_CMD send-keys -l -t "$pane" "$skill_cmd"
    fi
    sleep 3
  done
}

# --- Kill old monitors ---
for pid_file in /tmp/orca-monitor-"${SESSION}"-*.pid; do
  [ -f "$pid_file" ] || continue
  kill "$(cat "$pid_file")" 2>/dev/null || true
  rm -f "$pid_file"
done

# --- Start monitors for codex panes ---
WORKER_BIN_CHECK="$(model_bin "$WORKER_MODEL")"
if [ "$WORKER_BIN_CHECK" = "codex" ]; then
  i=1
  for label in $WORKER_LABELS; do
    _skill_monitor "$SESSION" "$SESSION:main.${i}" "worker" &
    echo $! > "/tmp/orca-monitor-${SESSION}-worker-${i}.pid"
    i=$((i + 1))
  done
fi

LEAD_BIN_CHECK="$(model_bin "$LEAD_MODEL")"
if [ "$LEAD_BIN_CHECK" = "codex" ]; then
  _skill_monitor "$SESSION" "$SESSION:main.0" "lead" &
  echo $! > "/tmp/orca-monitor-${SESSION}-lead.pid"
fi

# --- Focus lead pane ---
$TMUX_CMD select-pane -t "$SESSION:main.0"

# --- Attach ---
$TMUX_CMD attach -t "$SESSION"
