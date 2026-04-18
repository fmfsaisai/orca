#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Orca Install ==="
echo ""

# --- Check prerequisites ---
errors=0

if ! command -v jq &>/dev/null; then
  echo "[ ] jq not installed -> brew install jq"
  errors=$((errors + 1))
else
  echo "[x] jq $(jq --version 2>&1)"
fi

if ! command -v tmux &>/dev/null; then
  echo "[ ] tmux not installed -> brew install tmux"
  errors=$((errors + 1))
else
  echo "[x] tmux $(tmux -V | awk '{print $2}')"
fi

if ! command -v claude &>/dev/null; then
  echo "[ ] Claude Code CLI not installed -> https://docs.anthropic.com/en/docs/claude-code"
  errors=$((errors + 1))
else
  echo "[x] Claude Code CLI"
fi

if ! command -v codex &>/dev/null; then
  echo "[ ] Codex CLI not installed -> npm install -g @openai/codex"
  errors=$((errors + 1))
else
  echo "[x] Codex CLI $(codex --version 2>&1 | head -1)"
fi

if (( errors > 0 )); then
  echo ""
  echo "Install missing components and re-run ./install.sh"
  exit 1
fi

echo ""

# --- Install smux ---
if command -v tmux-bridge &>/dev/null; then
  echo "[x] smux/tmux-bridge installed"
else
  echo "Installing smux ..."
  curl -fsSL https://shawnpana.com/smux/install.sh | bash
  export PATH="$HOME/.smux/bin:$PATH"
  echo ""
fi

# --- Ensure smux in PATH ---
if ! grep -q '.smux/bin' ~/.bash_profile 2>/dev/null && ! grep -q '.smux/bin' ~/.zshrc 2>/dev/null; then
  SHELL_RC=""
  if [[ -f ~/.zshrc ]]; then
    SHELL_RC=~/.zshrc
  elif [[ -f ~/.bash_profile ]]; then
    SHELL_RC=~/.bash_profile
  fi
  if [[ -n "$SHELL_RC" ]]; then
    echo "" >> "$SHELL_RC"
    echo "# smux" >> "$SHELL_RC"
    echo 'export PATH="$HOME/.smux/bin:$PATH"' >> "$SHELL_RC"
    echo "[x] smux PATH added to $SHELL_RC"
  fi
fi

# --- Make scripts executable ---
# Convention: `_*.sh` are sourced helper libraries (e.g. _lib.sh) and must
# not be marked executable, otherwise `git status` stays dirty after every
# install and the file could be invoked directly by mistake.
for f in "$SCRIPT_DIR"/*.sh; do
  [[ "$(basename "$f")" == _* ]] && continue
  chmod +x "$f"
done
echo "[x] Script permissions set"

# --- Create global command ---
# Single entry point. Subcommands (stop, idle, ...) dispatched inside start.sh.
mkdir -p ~/.local/bin
ln -sfn "$SCRIPT_DIR/start.sh" ~/.local/bin/orca
# Clean up legacy per-subcommand symlinks from earlier installs (no-op if absent)
rm -f ~/.local/bin/orca-stop ~/.local/bin/orca-idle
echo "[x] Global command: orca -> ~/.local/bin/ (subcommands: stop, idle)"

# --- Check ~/.local/bin in PATH ---
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo ""
  echo "Warning: ~/.local/bin not in PATH. Add manually:"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
fi

# --- Register skill ---
mkdir -p ~/.claude/skills
ln -sfn "$SCRIPT_DIR/skills/orca" ~/.claude/skills/orca
echo "[x] Skill registered at ~/.claude/skills/orca (Claude Code)"

mkdir -p ~/.agents/skills
ln -sfn "$SCRIPT_DIR/skills/orca" ~/.agents/skills/orca
echo "[x] Skill registered at ~/.agents/skills/orca (Codex)"

# --- Register SessionStart hooks ---

CLAUDE_HOOK_TMP=$(mktemp)
# Elaborate hook: type /orca and submit it after CC has started.
# Why elaborate (not a plain echo of an instruction): in practice CC does NOT
# reliably auto-invoke the orca skill from a SessionStart system message.
# We have to type /orca into the input box and submit it.
# Why poll (not a fixed `sleep N`): a fixed delay either fires before CC is
# ready (the typed /orca becomes literal text) or fires while the user is
# already typing manually (race-condition garble). Polling for an empty
# prompt line (`^[[:space:]]*(>|❯|›)[[:space:]]*$`) fires as soon as CC
# accepts input — usually <1s — and naturally aborts when the user has
# typed anything (trailing non-whitespace breaks the match) or is stuck on
# a modal like the trust dialog (`❯ 1. Yes, I trust this folder` has
# non-whitespace after the cursor, so it does not falsely trigger). Max
# poll budget is 60s to absorb cold-start jitter and slow trust-dialog
# dismissal on the first orca-in-this-dir launch.
# Why `Enter` (not `C-m`): with tmux extended-keys on, CC negotiates the Kitty
# keyboard protocol and expects the extended Enter sequence. `C-m` sends raw \r
# which is then treated as literal text. `Enter` (named key) lets tmux emit
# whatever the inner program negotiated.
cat > "$CLAUDE_HOOK_TMP" << 'HOOKEOF'
[{"hooks":[{"type":"command","command":"[ -n \"$ORCA\" ] && nohup bash -c 'for i in $(seq 1 200); do sleep 0.3; tmux capture-pane -p -t \"$TMUX_PANE\" 2>/dev/null | grep -qE \"^[[:space:]]*(>|❯|›)[[:space:]]*\\$\" && { tmux send-keys -l -t \"$TMUX_PANE\" /orca; sleep 0.2; tmux send-keys -t \"$TMUX_PANE\" Enter; exit 0; }; done' >/dev/null 2>&1 &"}]}]
HOOKEOF

# install_or_update_hook <settings-file> <hook-tmp> <label>
# Scoped to orca-managed entries only: drops any existing SessionStart entry
# whose command contains the "$ORCA" signature, then appends the new orca
# entry. Foreign (non-orca) entries are preserved untouched. Re-running
# install.sh therefore both upgrades legacy orca hooks and leaves coexisting
# tools alone.
install_or_update_hook() {
  local settings="$1" hook_tmp="$2" label="$3"
  [ -f "$settings" ] || echo '{}' > "$settings"
  # Two-step write so a jq failure does not leave the success message lying.
  # `set -e` does not catch failures inside `cmd && cmd` (checked context),
  # so we test jq explicitly and surface the error.
  if ! jq --slurpfile hook "$hook_tmp" '
    .hooks //= {} |
    .hooks.SessionStart = (
      ((.hooks.SessionStart // []) | map(select(.hooks | tostring | test("\\$ORCA") | not)))
      + $hook[0]
    )
  ' "$settings" > "$settings.tmp"; then
    rm -f "$settings.tmp"
    echo "[!] $label SessionStart hook install failed (jq error)" >&2
    return 1
  fi
  mv "$settings.tmp" "$settings"
  echo "[x] $label SessionStart hook installed (orca-managed)"
}

# cleanup_orca_hook <settings-file> <label>
# Removes any SessionStart entries carrying the $ORCA signature, then collapses
# the surrounding scaffolding: empty SessionStart array → drop the key; empty
# hooks object → drop the key; resulting empty file → delete it. Leaves
# unrelated entries / top-level keys untouched.
cleanup_orca_hook() {
  local settings="$1" label="$2"
  [ -f "$settings" ] || return 0
  jq -e '.hooks.SessionStart' "$settings" >/dev/null 2>&1 || return 0
  if ! jq '
    .hooks.SessionStart |= map(select(.hooks | tostring | test("\\$ORCA") | not)) |
    if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end |
    if (.hooks // {} | length) == 0 then del(.hooks) else . end
  ' "$settings" > "$settings.tmp"; then
    rm -f "$settings.tmp"
    echo "[!] $label hooks cleanup failed (jq error)" >&2
    return 1
  fi
  mv "$settings.tmp" "$settings"
  if [ "$(jq -c '.' "$settings")" = "{}" ]; then
    rm -f "$settings"
    echo "[x] $label hooks file removed (orca was the only entry)"
  else
    echo "[x] $label SessionStart orca-managed entries removed"
  fi
}

# Claude Code hook
install_or_update_hook ~/.claude/settings.json "$CLAUDE_HOOK_TMP" "Claude Code"

# Codex worker activation is fully owned by start.sh ($CODER_CMD '$orca' on
# launch + _skill_monitor banner-watcher after /clear), so codex needs no
# SessionStart hook from us. Strip any legacy orca-managed entry from prior
# installs so codex's hook runner doesn't choke on a stale `[ -n "$ORCA" ]`
# command (which exits 1 outside an orca pane and breaks codex sessions).
cleanup_orca_hook ~/.codex/hooks.json "Codex"

rm -f "$CLAUDE_HOOK_TMP"

echo ""
echo "=== Install complete ==="
echo ""
echo "Usage:"
echo "  cd /path/to/your/project"
echo "  orca               # start (claude lead + codex worker)"
echo "  orca stop          # stop current dir's instance"
echo "  orca ps            # list all running instances"
echo "  orca rm <name>     # remove a specific instance (any dir)"
echo "  orca prune         # clean dead socket inodes"
echo "  orca idle          # wait for idle"
echo ""
