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
chmod +x "$SCRIPT_DIR"/*.sh
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
# Why `Enter` (not `C-m`): with tmux extended-keys on, CC negotiates the Kitty
# keyboard protocol and expects the extended Enter sequence. `C-m` sends raw \r
# which is then treated as literal text. `Enter` (named key) lets tmux emit
# whatever the inner program negotiated.
cat > "$CLAUDE_HOOK_TMP" << 'HOOKEOF'
[{"hooks":[{"type":"command","command":"[ -n \"$ORCA\" ] && nohup bash -c 'sleep 5; tmux send-keys -l -t \"$TMUX_PANE\" /orca; sleep 0.5; tmux send-keys -t \"$TMUX_PANE\" Enter' >/dev/null 2>&1 &"}]}]
HOOKEOF

CODEX_HOOK_TMP=$(mktemp)
cat > "$CODEX_HOOK_TMP" << 'HOOKEOF'
[{"hooks":[{"type":"command","command":"[ -n \"$ORCA\" ] && echo 'Orca active. Role: worker. Run $orca'"}]}]
HOOKEOF

# install_or_update_hook <settings-file> <hook-tmp> <label>
# - File missing: create with our hook
# - SessionStart absent: add ours alongside whatever else is in the file
# - SessionStart present and contains "$ORCA" signature: orca-managed, replace
#   so re-running install.sh upgrades legacy installs
# - SessionStart present without our signature: foreign hook, skip and warn
install_or_update_hook() {
  local settings="$1" hook_tmp="$2" label="$3"
  if [ ! -f "$settings" ]; then
    echo '{}' | jq --slurpfile hook "$hook_tmp" '{hooks: {SessionStart: $hook[0]}}' > "$settings"
    echo "[x] $label SessionStart hook created"
    return
  fi
  if ! jq -e '.hooks.SessionStart' "$settings" &>/dev/null; then
    jq --slurpfile hook "$hook_tmp" '.hooks = (.hooks // {}) + {SessionStart: $hook[0]}' \
      "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
    echo "[x] $label SessionStart hook registered"
    return
  fi
  if jq -e '.hooks.SessionStart | tostring | test("\\$ORCA")' "$settings" &>/dev/null; then
    jq --slurpfile hook "$hook_tmp" '.hooks.SessionStart = $hook[0]' \
      "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
    echo "[x] $label SessionStart hook updated (orca-managed)"
  else
    echo "[!] $label SessionStart hook exists and is not orca-managed, skipping"
    echo "    Manually merge orca's hook from install.sh if needed"
  fi
}

# Claude Code hook
install_or_update_hook ~/.claude/settings.json "$CLAUDE_HOOK_TMP" "Claude Code"

# Codex hook
mkdir -p ~/.codex
install_or_update_hook ~/.codex/hooks.json "$CODEX_HOOK_TMP" "Codex"

rm -f "$CLAUDE_HOOK_TMP" "$CODEX_HOOK_TMP"

echo ""
echo "=== Install complete ==="
echo ""
echo "Usage:"
echo "  cd /path/to/your/project"
echo "  orca               # start (default coder: codex)"
echo "  orca claude        # start with claude as worker"
echo "  orca stop          # stop current dir's instance"
echo "  orca ps            # list all running instances"
echo "  orca rm <name>     # remove a specific instance (any dir)"
echo "  orca prune         # clean dead socket inodes"
echo "  orca idle          # wait for idle"
echo ""
