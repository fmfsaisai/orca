#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# Canonicalize: see start.sh for rationale (macOS /tmp -> /private/tmp).
CURRENT_CWD=$(cd "$(pwd)" 2>/dev/null && pwd -P) || CURRENT_CWD="$(pwd)"
selected=()

resolve_targets() {
  local target row id type socket_name name cwd _a _c _p
  local seen_ids=() seen rc

  for target in "$@"; do
    rc=0
    row=$(resolve_target_by_id_or_name "$target") || rc=$?
    if [ "$rc" -eq 1 ]; then
      echo "(run 'orca ps' to see available ids and names)" >&2
      exit 1
    fi
    if [ "$rc" -eq 2 ]; then
      echo "Ambiguous instance name '$target'; use the exact id from 'orca ps'" >&2
      exit 1
    fi

    IFS='|' read -r type socket_name name _a _c _p cwd <<<"$row"
    id=$(short_id "$type:$name:$cwd")
    for seen in "${seen_ids[@]}"; do
      [ "$seen" = "$id" ] && continue 2
    done
    selected+=("$row")
    seen_ids+=("$id")
  done
}

if [ "$#" -eq 0 ]; then
  current_instances=()
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    current_instances+=("$row")
  done < <(list_all_instances_in_cwd "$CURRENT_CWD" | sort -t '|' -k5,5nr)

  if [ "${#current_instances[@]}" -eq 0 ]; then
    echo "No orca instances found in $(shorten_path "$CURRENT_CWD")"
    exit 0
  fi

  picker_rows=()
  for row in "${current_instances[@]}"; do
    IFS='|' read -r type socket_name name attached created panes cwd <<<"$row"
    id=$(short_id "$type:$name:$cwd")
    status=$([ "$attached" = "1" ] && echo "attached" || echo "detached")
    picker_rows+=("$id  $(format_picker_row "$name" "$status" "$panes" "$(format_uptime "$created")")")
  done

  if ! picks="$(pick_many_tui \
    "Stop which orcas?" \
    "" \
    "${picker_rows[@]}")"; then
    echo "Cancelled"
    exit 0
  fi

  if [ -z "$picks" ]; then
    echo "No instances selected"
    exit 0
  fi

  while IFS= read -r pick; do
    [ -n "$pick" ] || continue
    selected+=("${current_instances[$((pick - 1))]}")
  done <<<"$picks"
else
  resolve_targets "$@"
fi

summary=''
for row in "${selected[@]}"; do
  IFS='|' read -r type socket_name name attached created panes cwd <<<"$row"
  label="$name"
  if [ -n "$summary" ]; then
    summary="${summary}, ${label}"
  else
    summary="$label"
  fi
done

echo "About to stop: $summary"
read -rp "Proceed? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Cancelled"
  exit 0
fi

for row in "${selected[@]}"; do
  IFS='|' read -r type socket_name name attached created panes cwd <<<"$row"
  stop_instance "$type" "$socket_name" "$name" "$cwd"
  case "$type" in
    isolated)
      echo "Stopped isolated instance: $name"
      ;;
    main-tmux)
      echo "Stopped main-tmux session: $name"
      ;;
  esac
done
