#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Agent Orchestra 安装 ==="
echo ""

# --- 检查前置条件 ---
errors=0

if ! command -v jq &>/dev/null; then
  echo "[ ] jq 未安装 → brew install jq"
  errors=$((errors + 1))
else
  echo "[x] jq $(jq --version 2>&1)"
fi

if ! command -v tmux &>/dev/null; then
  echo "[ ] tmux 未安装 → brew install tmux"
  errors=$((errors + 1))
else
  echo "[x] tmux $(tmux -V | awk '{print $2}')"
fi

if ! command -v claude &>/dev/null; then
  echo "[ ] Claude Code CLI 未安装 → https://docs.anthropic.com/en/docs/claude-code"
  errors=$((errors + 1))
else
  echo "[x] Claude Code CLI"
fi

if ! command -v codex &>/dev/null; then
  echo "[ ] Codex CLI 未安装 → npm install -g @openai/codex"
  errors=$((errors + 1))
else
  echo "[x] Codex CLI $(codex --version 2>&1 | head -1)"
fi

if (( errors > 0 )); then
  echo ""
  echo "请先安装以上缺失组件，然后重新运行 ./install.sh"
  exit 1
fi

echo ""

# --- 安装 smux ---
if command -v tmux-bridge &>/dev/null; then
  echo "[x] smux/tmux-bridge 已安装"
else
  echo "安装 smux ..."
  curl -fsSL https://shawnpana.com/smux/install.sh | bash
  export PATH="$HOME/.smux/bin:$PATH"
  echo ""
fi

# --- 确保 smux 在 PATH 中 ---
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
    echo "[x] smux PATH 已添加到 $SHELL_RC"
  fi
fi

# --- 给脚本加执行权限 ---
chmod +x "$SCRIPT_DIR"/*.sh
echo "[x] 脚本执行权限"

# --- 创建全局命令 ---
mkdir -p ~/.local/bin
ln -sfn "$SCRIPT_DIR/start.sh" ~/.local/bin/orch
ln -sfn "$SCRIPT_DIR/stop.sh" ~/.local/bin/orch-stop
ln -sfn "$SCRIPT_DIR/wait-for-idle.sh" ~/.local/bin/orch-idle
echo "[x] 全局命令: orch, orch-stop, orch-idle → ~/.local/bin/"

# --- 检查 ~/.local/bin 是否在 PATH 中 ---
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo ""
  echo "警告: ~/.local/bin 不在 PATH 中，请手动添加:"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
fi

# --- 注册 Skill 到 Claude Code ---
mkdir -p ~/.claude/skills
ln -sfn "$SCRIPT_DIR/skills/orchestra" ~/.claude/skills/orchestra
echo "[x] Skill 已注册到 ~/.claude/skills/orchestra"

# --- 注册 SessionStart hooks ---

# 生成临时 hook JSON（避免 shell 转义问题）
CLAUDE_HOOK_TMP=$(mktemp)
cat > "$CLAUDE_HOOK_TMP" << 'HOOKEOF'
[{"hooks":[{"type":"command","command":"[ -n \"$ORCH\" ] && echo '你在 orchestra 协同环境中，角色: lead，请执行 /orchestra'"}]}]
HOOKEOF

CODEX_HOOK_TMP=$(mktemp)
cat > "$CODEX_HOOK_TMP" << 'HOOKEOF'
[{"hooks":[{"type":"command","command":"[ -n \"$ORCH\" ] && echo '你在 orchestra 协同环境中，角色: coder，请执行 $orchestra'"}]}]
HOOKEOF

# Claude Code hook
CLAUDE_SETTINGS=~/.claude/settings.json
if [ -f "$CLAUDE_SETTINGS" ]; then
  if jq -e '.hooks.SessionStart' "$CLAUDE_SETTINGS" &>/dev/null; then
    echo "[x] Claude Code SessionStart hook 已存在，跳过"
  else
    jq --slurpfile hook "$CLAUDE_HOOK_TMP" '.hooks = (.hooks // {}) + {SessionStart: $hook[0]}' \
      "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp" && mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
    echo "[x] Claude Code SessionStart hook 已注册"
  fi
else
  echo '{}' | jq --slurpfile hook "$CLAUDE_HOOK_TMP" '{hooks: {SessionStart: $hook[0]}}' > "$CLAUDE_SETTINGS"
  echo "[x] Claude Code SessionStart hook 已创建"
fi

# Codex hook
CODEX_HOOKS=~/.codex/hooks.json
mkdir -p ~/.codex
if [ -f "$CODEX_HOOKS" ]; then
  if jq -e '.hooks.SessionStart' "$CODEX_HOOKS" &>/dev/null; then
    echo "[x] Codex SessionStart hook 已存在，跳过"
  else
    jq --slurpfile hook "$CODEX_HOOK_TMP" '.hooks = (.hooks // {}) + {SessionStart: $hook[0]}' \
      "$CODEX_HOOKS" > "$CODEX_HOOKS.tmp" && mv "$CODEX_HOOKS.tmp" "$CODEX_HOOKS"
    echo "[x] Codex SessionStart hook 已注册"
  fi
else
  echo '{}' | jq --slurpfile hook "$CODEX_HOOK_TMP" '{hooks: {SessionStart: $hook[0]}}' > "$CODEX_HOOKS"
  echo "[x] Codex SessionStart hook 已创建"
fi

rm -f "$CLAUDE_HOOK_TMP" "$CODEX_HOOK_TMP"

echo ""
echo "=== 安装完成 ==="
echo ""
echo "使用方法:"
echo "  cd /path/to/your/project"
echo "  orch          # 启动"
echo "  orch-stop     # 停止"
echo ""
