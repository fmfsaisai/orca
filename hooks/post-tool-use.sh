#!/usr/bin/env bash
# PostToolUse hook: worker writes heartbeat timestamp.
[[ -z "${ORCA:-}" ]] && exit 0
[[ "${ORCA_ROLE:-}" != "worker" ]] && exit 0

HEARTBEAT_DIR="${ORCA_ROOT:-.}/.orca/heartbeat/${ORCA_SESSION:-shared}"
mkdir -p "$HEARTBEAT_DIR"
date +%s > "$HEARTBEAT_DIR/${ORCA_WORKER_ID:-0}"
