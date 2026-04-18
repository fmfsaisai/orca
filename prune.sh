#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

dir=$(tmux_socket_dir)
if [ -z "$dir" ]; then
  echo "No tmux socket directory found; nothing to prune"
  exit 0
fi

count=0
while IFS= read -r sock_name; do
  [ -z "$sock_name" ] && continue
  rm -f "$dir/$sock_name" && count=$((count + 1))
  echo "Removed dead socket: $sock_name"
done < <(list_dedicated_dead)

if [ "$count" -eq 0 ]; then
  echo "No dead sockets to clean"
else
  echo "Cleaned $count dead socket$([ "$count" -gt 1 ] && echo s)"
fi
