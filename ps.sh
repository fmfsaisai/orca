#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# Collect rows: each row is "NAME\tTYPE\tSTATUS\tCWD\tPANES\tUPTIME"
rows=()

# Dedicated servers
while IFS= read -r sock_name; do
  [ -z "$sock_name" ] && continue
  # tmux ls on a per-server socket; only one session expected per dedicated server
  info=$(tmux -L "$sock_name" ls -F '#{session_name}|#{session_attached}|#{session_created}|#{session_windows}' 2>/dev/null | head -1)
  [ -z "$info" ] && continue
  IFS='|' read -r name attached created windows <<<"$info"
  status=$([ "$attached" = "1" ] && echo "attached" || echo "detached")
  # Pane count = sum across all windows; for orca it's typically 2 in window 'main'
  panes=$(tmux -L "$sock_name" list-panes -s -t "$name" 2>/dev/null | wc -l | tr -d ' ')
  cwd=$(tmux -L "$sock_name" display-message -p -t "$name:0.0" '#{pane_current_path}' 2>/dev/null || echo '?')
  rows+=("$name	dedicated	$status	$(shorten_path "$cwd")	$panes	$(format_uptime "$created")")
done < <(list_dedicated_live)

# Legacy sessions on user's main tmux server
while IFS= read -r sname; do
  [ -z "$sname" ] && continue
  info=$(tmux ls -F '#{session_name}|#{session_attached}|#{session_created}|#{session_windows}' 2>/dev/null \
    | grep -E "^${sname}\|" | head -1)
  [ -z "$info" ] && continue
  IFS='|' read -r name attached created windows <<<"$info"
  status=$([ "$attached" = "1" ] && echo "attached" || echo "detached")
  panes=$(tmux list-panes -s -t "$name" 2>/dev/null | wc -l | tr -d ' ')
  cwd=$(tmux display-message -p -t "$name:0.0" '#{pane_current_path}' 2>/dev/null || echo '?')
  rows+=("$name	legacy	$status	$(shorten_path "$cwd")	$panes	$(format_uptime "$created")")
done < <(list_legacy_sessions)

# Render table
if [ ${#rows[@]} -eq 0 ]; then
  echo "No orca instances running"
else
  {
    printf 'NAME\tTYPE\tSTATUS\tCWD\tPANES\tUPTIME\n'
    printf '%s\n' "${rows[@]}"
  } | column -t -s $'\t'
fi

# Dead socket hint
dead_count=$(list_dedicated_dead | wc -l | tr -d ' ')
if [ "$dead_count" -gt 0 ]; then
  echo
  echo "($dead_count dead socket$([ "$dead_count" -gt 1 ] && echo s) — run 'orca prune' to clean)"
fi
