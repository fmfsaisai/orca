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

rc=0
result=$(resolve_target_by_id_or_name "$target" 2>/dev/null) || rc=$?

# Dead-socket fast path: no live match, but a dead inode with that name exists.
if [ "$rc" -eq 1 ]; then
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
if [ "$rc" -eq 0 ]; then
  chosen="$result"
else
  matches=()
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    matches+=("$row")
  done <<<"$result"

  echo "Multiple instances named '$target' (use the id to skip this picker):"
  picker_rows=()
  for row in "${matches[@]}"; do
    IFS='|' read -r mtype _msock mname mattached mcreated mpanes mcwd <<<"$row"
    status=$([ "$mattached" = "1" ] && echo "attached" || echo "detached")
    picker_rows+=("$(format_picker_row "$mname" "$status" "$mpanes" "$(format_uptime "$mcreated")")  $mtype  cwd: $(shorten_path "$mcwd")")
  done

  if ! pick="$(pick_one "Pick one" "" "${picker_rows[@]}")"; then
    echo "Cancelled"
    exit 0
  fi
  chosen="${matches[$((pick - 1))]}"
fi

IFS='|' read -r ttype tsocket tname _ta _tc tpanes tcwd <<<"$chosen"
tid=$(short_id "$ttype:$tname:$tcwd")

echo
echo "About to remove:"
echo "  $tid  $ttype  $tname  ($tpanes panes, cwd: $(shorten_path "$tcwd"))"
read -rp "Proceed? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Cancelled"
  exit 0
fi

stop_instance "$ttype" "$tsocket" "$tname" "$tcwd"
case "$ttype" in
  isolated)  echo "Removed isolated instance: $tname" ;;
  main-tmux) echo "Removed main-tmux session: $tname" ;;
esac
