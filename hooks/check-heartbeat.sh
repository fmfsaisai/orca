#!/usr/bin/env bash
# PreToolUse hook: lead checks worker heartbeats.
[[ -z "${ORCA:-}" ]] && exit 0
[[ "${ORCA_ROLE:-}" != "lead" ]] && exit 0

HEARTBEAT_DIR="${ORCA_ROOT:-.}/.orca/heartbeat/${ORCA_SESSION:-shared}"
[[ ! -d "$HEARTBEAT_DIR" ]] && exit 0

COOLDOWN=30
now=$(date +%s)
idle_workers=()
total=0

for f in "$HEARTBEAT_DIR"/[0-9]*; do
  [[ -f "$f" ]] || continue
  total=$((total + 1))
  last=$(cat "$f")
  gap=$((now - last))
  id=$(basename "$f")
  if (( gap > COOLDOWN )); then
    idle_workers+=("worker-$id(${gap}s)")
  fi
done

if (( ${#idle_workers[@]} > 0 )); then
  if (( ${#idle_workers[@]} == total )); then
    echo "[orca] All $total workers idle: ${idle_workers[*]}"
  else
    echo "[orca] Idle: ${idle_workers[*]}"
  fi
fi
