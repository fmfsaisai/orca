#!/usr/bin/env bash
# Codex SessionStart hook for agent-orchestra
# 等待 Codex 回到 prompt 后自动发送 $orchestra 触发 Skill

# 1) 消费 stdin（hook 协议要求读取 payload）
cat > /dev/null

# 2) 输出合法 JSON（hook 协议要求 stdout 返回结果）
echo '{}'

# 3) 诊断日志（无论是否在 orchestra 环境都记录，方便排查）
echo "[$(date)] SessionStart hook fired: ORCH=${ORCH:-unset} TMUX_PANE=${TMUX_PANE:-unset}" >> /tmp/orch-hook-coder.log

# 4) 非 orchestra 环境直接退出
[ -z "$ORCH" ] && exit 0
[ -z "$TMUX_PANE" ] && exit 0

# 5) 后台：等待 Codex prompt 出现后发送 $orchestra + Enter
nohup bash -c '
  pane="$TMUX_PANE"
  for i in $(seq 1 60); do
    sleep 1
    out=$(tmux capture-pane -p -t "$pane" 2>/dev/null \
      | perl -pe "s/\e\[[0-9;]*[a-zA-Z]//g") || true
    if echo "$out" | grep -qE "^[[:space:]]*(>|❯|›)[[:space:]]|Find and fix a bug"; then
      tmux send-keys -l -t "$pane" "\$orchestra"
      sleep 0.5
      tmux send-keys -t "$pane" C-m
      echo "[$(date)] OK: sent \$orchestra to $pane"
      exit 0
    fi
  done
  echo "[$(date)] TIMEOUT: prompt not detected on $pane"
' >> /tmp/orch-hook-coder.log 2>&1 &

exit 0
