#!/usr/bin/env bash
# Shared helpers for orca subcommand scripts.
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

# Sanitize basename: tmux uses `.` and `:` as target separators
# (session:window.pane), so dirs containing them break tmux targeting.
sanitize_dirname() {
  basename "$1" | tr '.:' '--'
}

base_session_name() {
  printf 'orca-%s' "$(sanitize_dirname "$1")"
}

format_session_timestamp() {
  local epoch="$1"
  if date -r "$epoch" '+%Y%m%d%H%M%S' >/dev/null 2>&1; then
    date -r "$epoch" '+%Y%m%d%H%M%S'
  else
    date -d "@$epoch" '+%Y%m%d%H%M%S'
  fi
}

socket_name_exists() {
  local socket_name="$1"
  local dir; dir=$(tmux_socket_dir)
  [ -n "$dir" ] && [ -S "$dir/$socket_name" ]
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

# Emit all live orca instances as:
# type|socket_name|session_name|attached(0|1)|created_epoch|panes|cwd
#
# Pane count comes from #{window_panes} of window 0. orca always creates one
# window named 'main', so this is the total pane count under that contract; a
# user who manually adds windows would see an undercount.
list_all_instances() {
  local sock_name info name attached created panes cwd legacy_table

  while IFS= read -r sock_name; do
    [ -n "$sock_name" ] || continue
    info=$(tmux -L "$sock_name" list-sessions \
      -F '#{session_name}|#{session_attached}|#{session_created}' \
      2>/dev/null) || continue
    [ -n "$info" ] || continue
    IFS='|' read -r name attached created <<<"$info"
    [ -n "$name" ] || continue
    info=$(tmux -L "$sock_name" display-message -p -t "${name}:0.0" \
      -F '#{window_panes}|#{pane_current_path}' 2>/dev/null) || info='?|?'
    IFS='|' read -r panes cwd <<<"$info"
    printf 'isolated|%s|%s|%s|%s|%s|%s\n' "$sock_name" "$name" "$attached" "$created" "$panes" "$cwd"
  done < <(list_dedicated_live)

  legacy_table=$(tmux ls -F '#{session_name}|#{session_attached}|#{session_created}' 2>/dev/null || true)
  [ -n "$legacy_table" ] || return 0
  while IFS='|' read -r name attached created; do
    case "$name" in orca-*) ;; *) continue ;; esac
    info=$(tmux display-message -p -t "${name}:0.0" \
      -F '#{window_panes}|#{pane_current_path}' 2>/dev/null) || info='?|?'
    IFS='|' read -r panes cwd <<<"$info"
    printf 'main-tmux||%s|%s|%s|%s|%s\n' "$name" "$attached" "$created" "$panes" "$cwd"
  done <<<"$legacy_table"
}

# Emit dedicated instances in the given cwd as:
# socket_name|session_name|attached(0|1)|created_epoch|panes
list_instances_in_cwd() {
  local target_cwd="$1"
  local type socket_name session_name attached created panes cwd

  while IFS='|' read -r type socket_name session_name attached created panes cwd; do
    [ "$type" = "isolated" ] || continue
    [ "$cwd" = "$target_cwd" ] || continue
    printf '%s|%s|%s|%s|%s\n' "$socket_name" "$session_name" "$attached" "$created" "$panes"
  done < <(list_all_instances)
}

# Emit all instances in the given cwd as:
# type|socket_name|session_name|attached(0|1)|created_epoch|panes|cwd
list_all_instances_in_cwd() {
  local target_cwd="$1"
  local type socket_name session_name attached created panes cwd

  while IFS='|' read -r type socket_name session_name attached created panes cwd; do
    [ "$cwd" = "$target_cwd" ] || continue
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
      "$type" "$socket_name" "$session_name" "$attached" "$created" "$panes" "$cwd"
  done < <(list_all_instances)
}

instance_name_exists() {
  local target_name="$1"
  local _t _s session_name _a _c _p _w

  while IFS='|' read -r _t _s session_name _a _c _p _w; do
    [ "$session_name" = "$target_name" ] && return 0
  done < <(list_all_instances)
  return 1
}

next_session_name() {
  local cwd="$1"
  local base_name epoch stamp candidate

  base_name=$(base_session_name "$cwd")
  epoch=$(date +%s)

  while :; do
    stamp=$(format_session_timestamp "$epoch")
    candidate="${base_name}-${stamp}"
    if ! socket_name_exists "$candidate" && ! instance_name_exists "$candidate"; then
      printf '%s\n' "$candidate"
      return
    fi
    epoch=$((epoch + 1))
  done
}

# Resolve a target (short_id or session name) to one row from
# list_all_instances. Caller decides what to do on ambiguity.
# Exit codes:
#   0 — unique match (one row on stdout)
#   1 — no match (error on stderr)
#   2 — multiple matches (all matching rows on stdout)
resolve_target_by_id_or_name() {
  local target="$1"
  local row id type socket_name name attached created panes cwd
  local matches=()

  while IFS='|' read -r type socket_name name attached created panes cwd; do
    if is_short_id "$target"; then
      id=$(short_id "$type:$name:$cwd")
      [ "$id" = "$target" ] && matches+=("$type|$socket_name|$name|$attached|$created|$panes|$cwd")
    else
      [ "$name" = "$target" ] && matches+=("$type|$socket_name|$name|$attached|$created|$panes|$cwd")
    fi
  done < <(list_all_instances)

  case "${#matches[@]}" in
    0) echo "No orca instance matches '$target'" >&2; return 1 ;;
    1) printf '%s\n' "${matches[0]}"; return 0 ;;
    *) printf '%s\n' "${matches[@]}"; return 2 ;;
  esac
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

format_picker_row() {
  local session_name="$1"
  local status="$2"
  local panes="$3"
  local uptime="$4"

  printf '%-32s  %-8s  %5s panes  %s' "$session_name" "$status" "$panes" "$uptime"
}

# Numbered single-select picker.
# Usage: pick_one PROMPT NEW_LABEL OPTION1 [OPTION2 ...]
# - NEW_LABEL: empty disables the "n) ..." choice; otherwise shown as `n)`
# - Empty input picks option 1 (default).
# Output: 1-based index, or "NEW" when user picks the new option.
# Returns 1 on quit/cancel.
pick_one() {
  local prompt="$1"
  local new_label="$2"
  shift 2
  local options=("$@")
  local count="${#options[@]}"
  local i choice range_suffix

  [ "$count" -gt 0 ] || return 1

  for ((i = 0; i < count; i++)); do
    if [ "$i" -eq 0 ]; then
      printf '  %d) %s  <- default\n' "$((i + 1))" "${options[$i]}"
    else
      printf '  %d) %s\n' "$((i + 1))" "${options[$i]}"
    fi
  done

  if [ -n "$new_label" ]; then
    printf '  n) %s\n' "$new_label"
    range_suffix="1-${count}/n/q"
  else
    range_suffix="1-${count}/q"
  fi

  while :; do
    read -rp "${prompt} [${range_suffix}] (default: 1): " choice
    case "$choice" in
      "")
        printf '1\n'
        return 0
        ;;
      [qQ])
        return 1
        ;;
      [nN])
        if [ -n "$new_label" ]; then
          printf 'NEW\n'
          return 0
        fi
        ;;
    esac

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
      printf '%s\n' "$choice"
      return 0
    fi

    echo "Invalid choice" >&2
  done
}

# TUI single-select renderer — file-scope, reads state via dynamic scope
# from pick_one_tui's locals (prompt, hint, count, current, options).
# Reuses _pick_many_clear (lines is set by the caller to match this layout).
_pick_one_tui_render() {
  local row
  tput rc
  printf '%s' "$prompt"
  tput el
  printf '\n'
  if [ -n "$hint" ]; then
    printf '%s' "$hint"
    tput el
    printf '\n'
  fi
  for ((row = 0; row < count; row++)); do
    if [ "$row" -eq "$current" ]; then
      printf '\033[38;5;117m> %s\033[0m' "${options[$row]}"
    else
      printf '  %s' "${options[$row]}"
    fi
    tput el
    if [ "$row" -lt $((count - 1)) ]; then
      printf '\n'
    fi
  done
}

# TUI single-select picker. Last appended option (when new_label non-empty)
# is the "new" entry; picking it returns the literal string "NEW" instead of
# its index. Returns 1 on quit/cancel.
# Usage: pick_one_tui PROMPT HINT NEW_LABEL OPTION1 [OPTION2 ...]
pick_one_tui() {
  local prompt="$1"
  local hint="$2"
  local new_label="$3"
  shift 3
  local options=("$@")

  if [ -n "$new_label" ]; then
    options+=("$new_label")
  fi

  local count="${#options[@]}"
  [ "$count" -gt 0 ] || return 1
  if ! { : >/dev/tty; } 2>/dev/null; then
    echo "Error: picker requires a TTY" >&2
    return 1
  fi

  (
    # stdout is captured by `$(...)`; route UI to /dev/tty and keep the
    # original stdout on FD 5 for emitting the result.
    exec 5>&1 >/dev/tty </dev/tty

    local current=0
    local lines=$((count + 1))
    [ -n "$hint" ] && lines=$((lines + 1))
    local key extra

    trap '_pick_many_clear 2>/dev/null || true; tput cnorm 2>/dev/null || true' EXIT

    tput sc
    tput civis
    _pick_one_tui_render

    while :; do
      IFS= read -rsn1 key || continue
      if [ "$key" = $'\e' ]; then
        extra=''
        read -rsn2 -t 0.001 extra || true
        key="${key}${extra}"
      fi

      case "$key" in
        $'\e[A'|k)
          if [ "$current" -gt 0 ]; then
            current=$((current - 1))
          else
            current=$((count - 1))
          fi
          ;;
        $'\e[B'|j)
          if [ "$current" -lt $((count - 1)) ]; then
            current=$((current + 1))
          else
            current=0
          fi
          ;;
        q|Q|$'\e')
          exit 1
          ;;
        $'\n'|$'\r'|'')
          if [ -n "$new_label" ] && [ "$current" -eq $((count - 1)) ]; then
            printf 'NEW' >&5
          else
            printf '%d' $((current + 1)) >&5
          fi
          exit 0
          ;;
      esac

      _pick_one_tui_render
    done
  )
}

# TUI checkbox helpers — file-scope so they aren't redefined per call. They
# read picker state via dynamic scope from pick_many_tui's locals
# (prompt, hint, count, current, lines, selected, options).
_pick_many_render() {
  local row marker
  tput rc
  printf '%s' "$prompt"
  tput el
  printf '\n'
  if [ -n "$hint" ]; then
    printf '%s' "$hint"
    tput el
    printf '\n'
  fi
  for ((row = 0; row < count; row++)); do
    marker='[ ]'
    [ "${selected[$row]}" -eq 1 ] && marker='[x]'
    if [ "$row" -eq "$current" ]; then
      printf '\033[38;5;117m%s %s\033[0m' "$marker" "${options[$row]}"
    else
      printf '%s %s' "$marker" "${options[$row]}"
    fi
    tput el
    if [ "$row" -lt $((count - 1)) ]; then
      printf '\n'
    fi
  done
}

_pick_many_clear() {
  local row
  tput rc
  for ((row = 0; row < lines; row++)); do
    tput el
    if [ "$row" -lt $((lines - 1)) ]; then
      tput cud1
    fi
  done
  tput rc
  tput cnorm
}

# TUI multi-select picker. Returns picked indices (1-based) on stdout, one
# per line. Returns 1 on quit/cancel.
# Wrapped in a subshell so the EXIT trap reliably restores cursor + screen
# state even if the body errors out under `set -e`.
pick_many_tui() {
  local prompt="$1"
  local hint="$2"
  shift 2
  local options=("$@")
  local count="${#options[@]}"

  [ "$count" -gt 0 ] || return 0
  if ! { : >/dev/tty; } 2>/dev/null; then
    echo "Error: stop picker requires a TTY" >&2
    return 1
  fi

  (
    # stdout is captured by `$(...)`; route UI to /dev/tty and keep the
    # original stdout on FD 5 for emitting the result.
    exec 5>&1 >/dev/tty </dev/tty

    local current=0
    local lines=$((count + 1))
    [ -n "$hint" ] && lines=$((lines + 1))
    local key extra output i
    local -a selected
    for ((i = 0; i < count; i++)); do
      selected[$i]=0
    done

    trap '_pick_many_clear 2>/dev/null || true; tput cnorm 2>/dev/null || true' EXIT

    tput sc
    tput civis
    _pick_many_render

    while :; do
      IFS= read -rsn1 key || continue
      if [ "$key" = $'\e' ]; then
        extra=''
        read -rsn2 -t 0.001 extra || true
        key="${key}${extra}"
      fi

      case "$key" in
        $'\e[A'|k)
          if [ "$current" -gt 0 ]; then
            current=$((current - 1))
          else
            current=$((count - 1))
          fi
          ;;
        $'\e[B'|j)
          if [ "$current" -lt $((count - 1)) ]; then
            current=$((current + 1))
          else
            current=0
          fi
          ;;
        ' ')
          if [ "${selected[$current]}" -eq 1 ]; then
            selected[$current]=0
          else
            selected[$current]=1
          fi
          ;;
        q|Q|$'\e')
          exit 1
          ;;
        $'\n'|$'\r'|'')
          output=''
          for ((i = 0; i < count; i++)); do
            if [ "${selected[$i]}" -eq 1 ]; then
              output="${output}$((i + 1))"$'\n'
            fi
          done
          printf '%s' "$output" >&5
          exit 0
          ;;
      esac

      _pick_many_render
    done
  )
}

# Short, stable hash id for an instance. Input should be a unique tuple of the
# instance's stable attributes (e.g. "isolated:orca-foo:/path/to/cwd"). 6 hex
# chars = 16M possibilities, ample headroom for the handful of instances a
# user has, with a comfortable margin against accidental name collisions.
# Tries md5 (macOS), md5sum (Linux), shasum in that order — at least one is
# always present on macOS/Linux.
short_id() {
  local input="$1"
  if command -v md5 &>/dev/null; then
    printf '%s' "$input" | md5 -q | cut -c1-6
  elif command -v md5sum &>/dev/null; then
    printf '%s' "$input" | md5sum | cut -c1-6
  else
    printf '%s' "$input" | shasum | cut -c1-6
  fi
}

# True if input looks like a short_id (6 lowercase hex chars).
is_short_id() {
  [[ "$1" =~ ^[0-9a-f]{6}$ ]]
}

cleanup_monitor_pids() {
  local session_name="$1"
  local pid_file monitor_pid

  for pid_file in /tmp/orca-monitor-"${session_name}"-*.pid; do
    [ -f "$pid_file" ] || continue
    kill "$(cat "$pid_file")" 2>/dev/null || true
    rm -f "$pid_file"
  done

  monitor_pid="/tmp/orca-monitor-${session_name}.pid"
  if [ -f "$monitor_pid" ]; then
    kill "$(cat "$monitor_pid")" 2>/dev/null || true
    rm -f "$monitor_pid"
  fi
}

cleanup_heartbeat_dir() {
  local repo_root="$1"
  local session_name="$2"
  local dir="${repo_root}/.orca/heartbeat/${session_name}"

  rm -rf "$dir" 2>/dev/null || true
}

stop_instance() {
  local type="$1"
  local socket_name="$2"
  local session_name="$3"
  local repo_root="$4"

  cleanup_monitor_pids "$session_name"
  cleanup_heartbeat_dir "$repo_root" "$session_name"

  case "$type" in
    isolated)
      tmux -L "$socket_name" kill-server 2>/dev/null || true
      ;;
    main-tmux)
      tmux kill-session -t "$session_name" 2>/dev/null || true
      ;;
  esac
}
