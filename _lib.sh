#!/usr/bin/env bash
# Shared helpers for orca subcommand scripts (ps, rm, prune).
# Sourced; not executable on its own.

# Directory tmux uses for per-user sockets. macOS symlinks /tmp -> /private/tmp,
# tmux resolves to /private/tmp; check both for portability with Linux.
tmux_socket_dir() {
  local uid; uid=$(id -u)
  for d in "/private/tmp/tmux-${uid}" "/tmp/tmux-${uid}"; do
    [ -d "$d" ] && { echo "$d"; return; }
  done
}

# Returns 0 if the socket exists but no tmux server is responding.
is_dead_socket() {
  local sock="$1"
  [ -S "$sock" ] || return 1
  ! tmux -S "$sock" list-sessions &>/dev/null
}

# List all live dedicated orca sockets (one socket name per line).
list_dedicated_live() {
  local dir; dir=$(tmux_socket_dir)
  [ -n "$dir" ] || return 0
  for sock in "$dir"/orca-*; do
    [ -S "$sock" ] || continue
    if tmux -S "$sock" list-sessions &>/dev/null; then
      basename "$sock"
    fi
  done
}

# List all dead orca socket inodes (one socket name per line).
list_dedicated_dead() {
  local dir; dir=$(tmux_socket_dir)
  [ -n "$dir" ] || return 0
  for sock in "$dir"/orca-*; do
    [ -S "$sock" ] || continue
    if ! tmux -S "$sock" list-sessions &>/dev/null; then
      basename "$sock"
    fi
  done
}

# List orca-named sessions on the user's main tmux server (one name per line).
list_legacy_sessions() {
  tmux ls -F '#{session_name}' 2>/dev/null | grep -E '^orca-' || true
}

# Format Unix-epoch seconds-since timestamp into compact uptime (e.g. 3h12m, 28m).
format_uptime() {
  local created="$1"
  local now; now=$(date +%s)
  local elapsed=$(( now - created ))
  if (( elapsed < 60 )); then
    printf '%ds' "$elapsed"
  elif (( elapsed < 3600 )); then
    printf '%dm' $(( elapsed / 60 ))
  elif (( elapsed < 86400 )); then
    printf '%dh%dm' $(( elapsed / 3600 )) $(( (elapsed % 3600) / 60 ))
  else
    printf '%dd%dh' $(( elapsed / 86400 )) $(( (elapsed % 86400) / 3600 ))
  fi
}

# Replace $HOME with ~ in a path for compact display.
# NOTE: a bare `~` in the replacement gets tilde-expanded back to $HOME,
# nullifying the substitution. Quote it to keep it literal.
shorten_path() {
  local path="$1"
  printf '%s' "${path/#$HOME/"~"}"
}

# Color helpers. Emit ANSI escapes only when stdout is a TTY so piping to
# a file or `less -R` does not get garbled.
if [ -t 1 ]; then
  COLOR_GREEN=$'\033[32m'
  COLOR_RED=$'\033[31m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_GREEN=''
  COLOR_RED=''
  COLOR_RESET=''
fi

# Wrap a STATUS value (`attached` / `detached`) in its color.
color_status() {
  case "$1" in
    attached) printf '%s%s%s' "$COLOR_GREEN" "$1" "$COLOR_RESET" ;;
    detached) printf '%s%s%s' "$COLOR_RED"   "$1" "$COLOR_RESET" ;;
    *)        printf '%s' "$1" ;;
  esac
}
