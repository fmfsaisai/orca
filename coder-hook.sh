#!/usr/bin/env bash
# Codex SessionStart hook for agent-orchestra
# 处理 new session（/clear）时的 skill 重新激活
# 启动时的激活由 start.sh prefill 完成

# 1) 读取 hook payload
input=$(cat)

# 2) 合法 JSON 响应
echo '{}'

# 3) 诊断日志
source_field=$(echo "$input" | grep -oE '"source"\s*:\s*"[^"]*"' | head -1)
echo "[$(date)] SessionStart hook: ${source_field:-unknown} ORCH=${ORCH:-unset} TMUX_PANE=${TMUX_PANE:-unset}" >> /tmp/orch-hook-coder.log

# 4) 非 orchestra 环境直接退出
[ -z "$ORCH" ] && exit 0
[ -z "$TMUX_PANE" ] && exit 0

# 5) startup 由 start.sh prefill 处理，hook 只处理 clear/resume
echo "$input" | grep -qE '"source"\s*:\s*"startup"' && exit 0

# 6) 后台：等待 Codex prompt 出现后发送 $orchestra + Enter
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
      echo "[$(date)] OK: sent \$orchestra to $pane (new session)"
      exit 0
    fi
  done
  echo "[$(date)] TIMEOUT: prompt not detected on $pane"
' >> /tmp/orch-hook-coder.log 2>&1 &

exit 0
