#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

rows=()
while IFS='|' read -r type socket_name name attached created panes cwd; do
  [ -n "$type" ] || continue
  status=$([ "$attached" = "1" ] && echo "attached" || echo "detached")
  id=$(short_id "$type:$name:$cwd")
  rows+=("$cwd|$created|$id|$name|$type|$status|$panes|$(format_uptime "$created")")
done < <(list_all_instances)

if [ "${#rows[@]}" -eq 0 ]; then
  echo "No orca instances running"
else
  w_id=2
  w_name=4
  w_type=4
  w_status=6
  w_panes=5
  w_uptime=6

  for row in "${rows[@]}"; do
    IFS='|' read -r cwd created id name type status panes uptime <<<"$row"
    (( ${#id} > w_id )) && w_id=${#id}
    (( ${#name} > w_name )) && w_name=${#name}
    (( ${#type} > w_type )) && w_type=${#type}
    (( ${#status} > w_status )) && w_status=${#status}
    (( ${#panes} > w_panes )) && w_panes=${#panes}
    (( ${#uptime} > w_uptime )) && w_uptime=${#uptime}
  done

  current_cwd=''
  while IFS='|' read -r cwd created id name type status panes uptime; do
    if [ "$cwd" != "$current_cwd" ]; then
      [ -z "$current_cwd" ] || echo
      echo "cwd: $(shorten_path "$cwd")"
      printf "  %-${w_id}s  %-${w_name}s  %-${w_type}s  %-${w_status}s  %${w_panes}s  %s\n" \
        "ID" "NAME" "TYPE" "STATUS" "PANES" "UPTIME"
      current_cwd="$cwd"
    fi

    printf "  %-${w_id}s  %-${w_name}s  %-${w_type}s  " "$id" "$name" "$type"
    printf "%s" "$(color_status "$status")"
    pad=$((w_status - ${#status}))
    (( pad > 0 )) && printf "%${pad}s" ""
    printf "  %${w_panes}s  %s\n" "$panes" "$uptime"
  done < <(printf '%s\n' "${rows[@]}" | sort -t '|' -k1,1 -k2,2n)
fi

dead_count=$(list_dedicated_dead | wc -l | tr -d ' ')
if [ "$dead_count" -gt 0 ]; then
  echo
  echo "($dead_count dead socket$([ "$dead_count" -gt 1 ] && echo s) — run 'orca prune' to clean)"
fi
