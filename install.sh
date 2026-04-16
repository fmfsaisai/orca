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

# --- Create global commands ---
mkdir -p ~/.local/bin
ln -sfn "$SCRIPT_DIR/start.sh" ~/.local/bin/orca
ln -sfn "$SCRIPT_DIR/stop.sh" ~/.local/bin/orca-stop
ln -sfn "$SCRIPT_DIR/wait-for-idle.sh" ~/.local/bin/orca-idle
echo "[x] Global commands: orca, orca-stop, orca-idle -> ~/.local/bin/"

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
cat > "$CLAUDE_HOOK_TMP" << 'HOOKEOF'
[{"hooks":[{"type":"command","command":"[ -n \"$ORCA\" ] && echo 'Orca active. Role: lead. Run /orca'"}]}]
HOOKEOF

CODEX_HOOK_TMP=$(mktemp)
cat > "$CODEX_HOOK_TMP" << 'HOOKEOF'
[{"hooks":[{"type":"command","command":"[ -n \"$ORCA\" ] && echo 'Orca active. Role: worker. Run $orca'"}]}]
HOOKEOF

# Claude Code hook
CLAUDE_SETTINGS=~/.claude/settings.json
if [ -f "$CLAUDE_SETTINGS" ]; then
  if jq -e '.hooks.SessionStart' "$CLAUDE_SETTINGS" &>/dev/null; then
    echo "[x] Claude Code SessionStart hook exists, skipping"
  else
    jq --slurpfile hook "$CLAUDE_HOOK_TMP" '.hooks = (.hooks // {}) + {SessionStart: $hook[0]}' \
      "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp" && mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
    echo "[x] Claude Code SessionStart hook registered"
  fi
else
  echo '{}' | jq --slurpfile hook "$CLAUDE_HOOK_TMP" '{hooks: {SessionStart: $hook[0]}}' > "$CLAUDE_SETTINGS"
  echo "[x] Claude Code SessionStart hook created"
fi

# Codex hook
CODEX_HOOKS=~/.codex/hooks.json
mkdir -p ~/.codex
if [ -f "$CODEX_HOOKS" ]; then
  if jq -e '.hooks.SessionStart' "$CODEX_HOOKS" &>/dev/null; then
    echo "[x] Codex SessionStart hook exists, skipping"
  else
    jq --slurpfile hook "$CODEX_HOOK_TMP" '.hooks = (.hooks // {}) + {SessionStart: $hook[0]}' \
      "$CODEX_HOOKS" > "$CODEX_HOOKS.tmp" && mv "$CODEX_HOOKS.tmp" "$CODEX_HOOKS"
    echo "[x] Codex SessionStart hook registered"
  fi
else
  echo '{}' | jq --slurpfile hook "$CODEX_HOOK_TMP" '{hooks: {SessionStart: $hook[0]}}' > "$CODEX_HOOKS"
  echo "[x] Codex SessionStart hook created"
fi

rm -f "$CLAUDE_HOOK_TMP" "$CODEX_HOOK_TMP"

echo ""
echo "=== Install complete ==="
echo ""
echo "Usage:"
echo "  cd /path/to/your/project"
echo "  orca          # start"
echo "  orca-stop     # stop"
echo ""
