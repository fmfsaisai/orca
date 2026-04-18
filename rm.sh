#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

if [ $# -lt 1 ]; then
  echo "Usage: orca rm <id|name>" >&2
  echo "       (use 'orca ps' to see available instances)" >&2
  exit 2
fi

target="$1"

# Enumerate every live instance once, computing id alongside. Each entry:
# "id|type|name|cwd|panes"
all=()

while IFS= read -r sock_name; do
  [ -z "$sock_name" ] && continue
  cwd=$(tmux -L "$sock_name" display-message -p -t "$sock_name:0.0" '#{pane_current_path}' 2>/dev/null || echo '?')
  panes=$(tmux -L "$sock_name" list-panes -s -t "$sock_name" 2>/dev/null | wc -l | tr -d ' ')
  id=$(short_id "isolated:$sock_name:$cwd")
  all+=("$id|isolated|$sock_name|$cwd|$panes")
done < <(list_dedicated_live)

while IFS= read -r sname; do
  [ -z "$sname" ] && continue
  cwd=$(tmux display-message -p -t "$sname:0.0" '#{pane_current_path}' 2>/dev/null || echo '?')
  panes=$(tmux list-panes -s -t "$sname" 2>/dev/null | wc -l | tr -d ' ')
  id=$(short_id "main-tmux:$sname:$cwd")
  all+=("$id|main-tmux|$sname|$cwd|$panes")
done < <(list_legacy_sessions)

# Match strategy:
#   1. If target looks like a short_id, match exclusively against ids (unique).
#   2. Otherwise, match against names. Multiple matches → picker.
matches=()
if is_short_id "$target"; then
  for entry in "${all[@]}"; do
    IFS='|' read -r eid _ _ _ _ <<<"$entry"
    [ "$eid" = "$target" ] && matches+=("$entry")
  done
else
  for entry in "${all[@]}"; do
    IFS='|' read -r _ _ ename _ _ <<<"$entry"
    [ "$ename" = "$target" ] && matches+=("$entry")
  done
fi

# Dead-socket fast path: no live match, but a dead inode with that name exists.
if [ ${#matches[@]} -eq 0 ]; then
  if ! is_short_id "$target"; then
    dir=$(tmux_socket_dir)
    if [ -n "$dir" ] && [ -S "$dir/$target" ] && is_dead_socket "$dir/$target"; then
      echo "'$target' has a dead socket inode (server already gone)."
      read -rp "Remove the inode? [y/N] " confirm
      if [[ "$confirm" == [yY] ]]; then
        rm -f "$dir/$target"
        echo "Removed dead socket: $target"
      else
        echo "Cancelled"
      fi
      exit 0
    fi
  fi
  echo "No orca instance matches '$target'" >&2
  echo "(run 'orca ps' to see available ids and names)" >&2
  exit 1
fi

# Pick target — direct if unique, picker if name-based ambiguity.
if [ ${#matches[@]} -eq 1 ]; then
  chosen="${matches[0]}"
else
  echo "Multiple instances named '$target' (use the id to skip this picker):"
  i=1
  for c in "${matches[@]}"; do
    IFS='|' read -r cid ctype cname ccwd cpanes <<<"$c"
    printf "  %d) %s  %s  %s  %s panes  cwd: %s\n" "$i" "$cid" "$ctype" "$cname" "$cpanes" "$(shorten_path "$ccwd")"
    i=$((i + 1))
  done
  echo
  read -rp "Pick one [1-${#matches[@]}]: " pick
  if ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$pick" -lt 1 ] || [ "$pick" -gt ${#matches[@]} ]; then
    echo "Invalid choice" >&2
    exit 1
  fi
  chosen="${matches[$((pick - 1))]}"
fi

IFS='|' read -r tid ttype tname tcwd tpanes <<<"$chosen"

echo
echo "About to remove:"
echo "  $tid  $ttype  $tname  ($tpanes panes, cwd: $(shorten_path "$tcwd"))"
read -rp "Proceed? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Cancelled"
  exit 0
fi

case "$ttype" in
  isolated)
    # Kill server (server only owns this one session, kill = clean env per D8)
    tmux -L "$tname" kill-server 2>/dev/null || true
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
