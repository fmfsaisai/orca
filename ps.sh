#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# Collect rows: each row is "NAME\tTYPE\tSTATUS\tCWD\tPANES\tUPTIME"
# STATUS is stored as plain text (attached/detached); coloring happens at print
# time so column widths can be computed from visible length.
rows=()

# Isolated instances: each on a per-instance dedicated tmux server (D8).
while IFS= read -r sock_name; do
  [ -z "$sock_name" ] && continue
  info=$(tmux -L "$sock_name" ls -F '#{session_name}|#{session_attached}|#{session_created}|#{session_windows}' 2>/dev/null | head -1)
  [ -z "$info" ] && continue
  IFS='|' read -r name attached created windows <<<"$info"
  status=$([ "$attached" = "1" ] && echo "attached" || echo "detached")
  panes=$(tmux -L "$sock_name" list-panes -s -t "$name" 2>/dev/null | wc -l | tr -d ' ')
  cwd=$(tmux -L "$sock_name" display-message -p -t "$name:0.0" '#{pane_current_path}' 2>/dev/null || echo '?')
  rows+=("$name	isolated	$status	$(shorten_path "$cwd")	$panes	$(format_uptime "$created")")
done < <(list_dedicated_live)

# Sessions on user's main tmux server (pre-D8 era; orphans after D8 upgrade).
while IFS= read -r sname; do
  [ -z "$sname" ] && continue
  info=$(tmux ls -F '#{session_name}|#{session_attached}|#{session_created}|#{session_windows}' 2>/dev/null \
    | grep -E "^${sname}\|" | head -1)
  [ -z "$info" ] && continue
  IFS='|' read -r name attached created windows <<<"$info"
  status=$([ "$attached" = "1" ] && echo "attached" || echo "detached")
  panes=$(tmux list-panes -s -t "$name" 2>/dev/null | wc -l | tr -d ' ')
  cwd=$(tmux display-message -p -t "$name:0.0" '#{pane_current_path}' 2>/dev/null || echo '?')
  rows+=("$name	main-tmux	$status	$(shorten_path "$cwd")	$panes	$(format_uptime "$created")")
done < <(list_legacy_sessions)

# Render
if [ ${#rows[@]} -eq 0 ]; then
  echo "No orca instances running"
else
  # Compute per-column max widths (visible length, no color codes involved here)
  w_name=4 w_type=4 w_status=6 w_cwd=3 w_panes=5 w_uptime=6
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r n t s c p u <<<"$row"
    (( ${#n} > w_name )) && w_name=${#n}
    (( ${#t} > w_type )) && w_type=${#t}
    (( ${#s} > w_status )) && w_status=${#s}
    (( ${#c} > w_cwd )) && w_cwd=${#c}
    (( ${#p} > w_panes )) && w_panes=${#p}
    (( ${#u} > w_uptime )) && w_uptime=${#u}
  done

  # Header
  printf "%-${w_name}s  %-${w_type}s  %-${w_status}s  %-${w_cwd}s  %${w_panes}s  %s\n" \
    "NAME" "TYPE" "STATUS" "CWD" "PANES" "UPTIME"

  # Rows — STATUS is colored, but pad as if uncolored so alignment holds.
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r n t s c p u <<<"$row"
    printf "%-${w_name}s  %-${w_type}s  " "$n" "$t"
    printf "%s" "$(color_status "$s")"
    pad=$(( w_status - ${#s} ))
    (( pad > 0 )) && printf "%${pad}s" ""
    printf "  %-${w_cwd}s  %${w_panes}s  %s\n" "$c" "$p" "$u"
  done
fi

# Dead socket hint
dead_count=$(list_dedicated_dead | wc -l | tr -d ' ')
if [ "$dead_count" -gt 0 ]; then
  echo
  echo "($dead_count dead socket$([ "$dead_count" -gt 1 ] && echo s) — run 'orca prune' to clean)"
fi
