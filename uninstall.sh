#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Args ---
# Default: dry-run + interactive confirm. `-y/--yes` skips the prompt.
# `-n/--dry-run` forces dry-run only (no prompt, no execution).
ASSUME_YES=0
FORCE_DRY=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes)     ASSUME_YES=1 ;;
    -n|--dry-run) FORCE_DRY=1 ;;
    -h|--help)
      cat <<EOF
Usage: ./uninstall.sh [options]

Removes orca-managed symlinks and hooks created by ./install.sh.

Options:
  -n, --dry-run   Show planned actions without applying them.
  -y, --yes       Skip the confirmation prompt and apply immediately.
  -h, --help      Show this help.

Default: dry-run preview, then prompt to apply.
EOF
      exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# --- Single-pass plan + apply ---
# Both passes call the same `remove_link` / `cleanup_hook` helpers; DRY_RUN
# flips whether they mutate the filesystem. This keeps preview and execution
# in lockstep — what you see in the dry-run is exactly what runs.
DRY_RUN=1

prefix() { [ "$DRY_RUN" = 1 ] && echo "[dry-run]" || echo "[x]"; }

remove_link() {
  local link="$1" expected_target="$2"
  if [ -L "$link" ]; then
    local actual
    actual="$(readlink "$link")"
    if [ "$actual" = "$expected_target" ]; then
      [ "$DRY_RUN" = 1 ] || rm -f "$link"
      echo "$(prefix) Remove symlink $link"
    else
      echo "[ ] Skip $link (points to $actual, not $expected_target)"
    fi
  elif [ -e "$link" ]; then
    echo "[ ] Skip $link (not a symlink)"
  fi
}

# cleanup_hook <settings-file> <hook-event> <signature-regex> <label>
# Removes entries whose serialized .hooks matches the signature regex, then
# collapses empty scaffolding (empty event array → drop key; empty hooks → drop).
cleanup_hook() {
  local settings="$1" event="$2" sig="$3" label="$4"
  [ -f "$settings" ] || return 0
  jq -e ".hooks.\"$event\"" "$settings" >/dev/null 2>&1 || return 0
  # Count matching entries up front so dry-run can report something meaningful.
  local n
  n="$(jq --arg event "$event" --arg sig "$sig" \
    '[.hooks[$event][] | select(.hooks | tostring | test($sig))] | length' \
    "$settings")"
  [ "$n" -gt 0 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] Remove $n $label $event entr$([ "$n" = 1 ] && echo y || echo ies) from $settings:"
    # Pretty-print each matched entry, indented, so the user can verify the
    # actual content (commands, matchers) before applying.
    jq --arg event "$event" --arg sig "$sig" \
      '.hooks[$event][] | select(.hooks | tostring | test($sig))' \
      "$settings" | sed 's/^/    /'
    return 0
  fi
  if ! jq --arg event "$event" --arg sig "$sig" '
    .hooks[$event] |= map(select(.hooks | tostring | test($sig) | not)) |
    if (.hooks[$event] | length) == 0 then del(.hooks[$event]) else . end |
    if (.hooks // {} | length) == 0 then del(.hooks) else . end
  ' "$settings" > "$settings.tmp"; then
    rm -f "$settings.tmp"
    echo "[!] $label $event cleanup failed (jq error)" >&2
    return 1
  fi
  mv "$settings.tmp" "$settings"
  echo "[x] Removed $n $label $event entr$([ "$n" = 1 ] && echo y || echo ies) from $settings"
}

# collapse_empty_json <file> <label>
collapse_empty_json() {
  local f="$1" label="$2"
  [ -f "$f" ] || return 0
  [ "$(jq -c '.' "$f" 2>/dev/null)" = "{}" ] || return 0
  [ "$DRY_RUN" = 1 ] || rm -f "$f"
  echo "$(prefix) Remove $f ($label was the only entry)"
}

run_plan() {
  remove_link ~/.local/bin/orca           "$SCRIPT_DIR/start.sh"
  remove_link ~/.local/bin/orca-worktree  "$SCRIPT_DIR/orca-worktree.sh"
  remove_link ~/.claude/skills/orca       "$SCRIPT_DIR/skills/orca"
  remove_link ~/.claude/skills/orca-code  "$SCRIPT_DIR/skills/workflows/code"
  remove_link ~/.agents/skills/orca       "$SCRIPT_DIR/skills/orca"
  remove_link ~/.agents/skills/orca-code  "$SCRIPT_DIR/skills/workflows/code"

  # Legacy per-subcommand symlinks from earlier installs.
  for legacy in ~/.local/bin/orca-stop ~/.local/bin/orca-idle; do
    if [ -e "$legacy" ] || [ -L "$legacy" ]; then
      [ "$DRY_RUN" = 1 ] || rm -f "$legacy"
      echo "$(prefix) Remove legacy $legacy"
    fi
  done

  if ! command -v jq &>/dev/null; then
    echo ""
    echo "[!] jq not found, cannot clean settings.json hooks. Install jq and re-run, or edit ~/.claude/settings.json manually."
    return 0
  fi

  local CLAUDE_SETTINGS=~/.claude/settings.json
  # SessionStart: install.sh tags its entry with the "$ORCA" env-var check.
  cleanup_hook "$CLAUDE_SETTINGS" "SessionStart" '\$ORCA' "Claude Code"
  # PostToolUse / PreToolUse: scope by command path into this repo's hooks/ dir.
  # Escape regex special chars in the path so jq's `test()` matches literally.
  local SCRIPT_DIR_RE
  SCRIPT_DIR_RE="$(printf '%s' "$SCRIPT_DIR/hooks/" | sed 's/[.[\*^$()+?{|\\]/\\&/g')"
  cleanup_hook "$CLAUDE_SETTINGS" "PostToolUse" "$SCRIPT_DIR_RE" "Claude Code"
  cleanup_hook "$CLAUDE_SETTINGS" "PreToolUse"  "$SCRIPT_DIR_RE" "Claude Code"
  collapse_empty_json "$CLAUDE_SETTINGS" "orca"

  # Codex: install.sh actively cleans this; mirror it here for completeness.
  cleanup_hook ~/.codex/hooks.json "SessionStart" '\$ORCA' "Codex"
  collapse_empty_json ~/.codex/hooks.json "orca"
}

echo "=== Orca Uninstall (dry-run preview) ==="
echo ""
run_plan
echo ""

if [ "$FORCE_DRY" = 1 ]; then
  echo "Dry-run only (--dry-run). Re-run without --dry-run to apply."
  exit 0
fi

if [ "$ASSUME_YES" = 0 ]; then
  if [ ! -t 0 ]; then
    echo "Non-interactive stdin and no --yes flag. Aborting without changes."
    echo "Re-run with -y/--yes to apply, or -n/--dry-run to suppress this notice."
    exit 1
  fi
  read -rp "Apply the changes above? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted. No changes made."; exit 0 ;;
  esac
fi

echo ""
echo "=== Applying ==="
echo ""
DRY_RUN=0
run_plan

echo ""
echo "=== Uninstall complete ==="
echo ""
echo "Not touched (manage manually if desired):"
echo "  - smux installation (~/.smux)"
echo "  - PATH entries in ~/.zshrc / ~/.bash_profile"
echo "  - Running orca tmux sessions (use 'orca ps' + 'orca rm <name>' before uninstalling)"
