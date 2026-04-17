#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

if [ $# -lt 1 ]; then
  echo "Usage: orca rm <name>" >&2
  echo "       (use 'orca ps' to see available names)" >&2
  exit 2
fi

target_name="$1"

# Discover candidates with the requested name
candidates=()  # entries: "type|name|cwd|panes"

while IFS= read -r sock_name; do
  [ "$sock_name" = "$target_name" ] || continue
  cwd=$(tmux -L "$sock_name" display-message -p -t "$sock_name:0.0" '#{pane_current_path}' 2>/dev/null || echo '?')
  panes=$(tmux -L "$sock_name" list-panes -s -t "$sock_name" 2>/dev/null | wc -l | tr -d ' ')
  candidates+=("isolated|$sock_name|$cwd|$panes")
done < <(list_dedicated_live)

while IFS= read -r sname; do
  [ "$sname" = "$target_name" ] || continue
  cwd=$(tmux display-message -p -t "$sname:0.0" '#{pane_current_path}' 2>/dev/null || echo '?')
  panes=$(tmux list-panes -s -t "$sname" 2>/dev/null | wc -l | tr -d ' ')
  candidates+=("main-tmux|$sname|$cwd|$panes")
done < <(list_legacy_sessions)

# Dead-socket fast path: no live candidates, but the requested name has a dead inode
if [ ${#candidates[@]} -eq 0 ]; then
  dir=$(tmux_socket_dir)
  if [ -n "$dir" ] && [ -S "$dir/$target_name" ] && is_dead_socket "$dir/$target_name"; then
    echo "'$target_name' has a dead socket inode (server already gone)."
    read -rp "Remove the inode? [y/N] " confirm
    if [[ "$confirm" == [yY] ]]; then
      rm -f "$dir/$target_name"
      echo "Removed dead socket: $target_name"
    else
      echo "Cancelled"
    fi
    exit 0
  fi
  echo "No orca instance named '$target_name'" >&2
  echo "(run 'orca ps' to see available instances)" >&2
  exit 1
fi

# Pick target — direct if unique, interactive picker if ambiguous
if [ ${#candidates[@]} -eq 1 ]; then
  chosen="${candidates[0]}"
else
  echo "Multiple instances named '$target_name':"
  i=1
  for c in "${candidates[@]}"; do
    IFS='|' read -r ctype cname ccwd cpanes <<<"$c"
    printf "  %d) %s (%s, %s panes, cwd: %s)\n" "$i" "$ctype" "$cname" "$cpanes" "$(shorten_path "$ccwd")"
    i=$((i + 1))
  done
  echo
  read -rp "Pick one [1-${#candidates[@]}]: " pick
  if ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$pick" -lt 1 ] || [ "$pick" -gt ${#candidates[@]} ]; then
    echo "Invalid choice" >&2
    exit 1
  fi
  chosen="${candidates[$((pick - 1))]}"
fi

IFS='|' read -r ttype tname tcwd tpanes <<<"$chosen"

echo
echo "About to remove:"
echo "  $tname ($ttype, $tpanes panes, cwd: $(shorten_path "$tcwd"))"
read -rp "Proceed? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Cancelled"
  exit 0
fi

case "$ttype" in
  isolated)
    # Kill server (server only owns this one session, kill = clean env per D8)
    tmux -L "$tname" kill-server 2>/dev/null || true
    # Clean monitor pid file if present
    monitor_pid="/tmp/orca-monitor-${tname}.pid"
    if [ -f "$monitor_pid" ]; then
      kill "$(cat "$monitor_pid")" 2>/dev/null || true
      rm -f "$monitor_pid"
    fi
    echo "Removed isolated instance: $tname"
    ;;
  main-tmux)
    tmux kill-session -t "$tname" 2>/dev/null || true
    echo "Removed main-tmux session: $tname"
    ;;
esac
