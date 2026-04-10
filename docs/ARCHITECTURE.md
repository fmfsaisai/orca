# Architecture Decision Record

## 架构概览

Lead (Claude Code) + Coder (Codex CLI) 双 agent 协同。tmux 分屏 + smux tmux-bridge 通信。

```
┌──────────────┬──────────────┐
│              │              │
│  Lead        │  Coder       │
│  (Claude)    │  (Codex)     │
│  调度+优化    │  编码+自查    │
│              │              │
└──────────────┴──────────────┘
       tmux session: orch-<dirname>
```

## 流水线

```
用户 → Lead 派活 → Coder 编码 → /review 自查 → 汇报 Lead → /simplify 优化 → 汇报用户
```

三层质量把关：编码 (GPT) → 自查修复 (GPT /review) → 独立优化 (Claude /simplify)

## 技术选型

### 为什么用 tmux 而不是 child_process 管道

- 管道方案容易日志错乱、死锁、进程僵死
- tmux session 天然持久化，断网重连还在
- send-keys / capture-pane 是成熟的 IPC 原语
- Human-in-the-loop：随时切到 pane 接管

### 为什么用 smux 而不是裸 tmux

- `tmux-bridge read coder 100` 比 `tmux capture-pane -t orch:main.1 -p -J -S -100` 省 token
- Read Guard 机制防止盲操作
- 本质只是 tmux 命令的语义化包装，无额外运行时

### 为什么 2 agent 而非 3 agent

初版设计了 Lead + Coder + Reviewer 三 agent。实践中发现：
- Codex 沙箱限制导致 Coder → Reviewer 通信困难
- Lead 做中转搬运消息浪费 context
- Codex `/review` + Claude `/simplify` 已覆盖代码审查需求
- 跨模型交叉（GPT 写 + Claude 审）比同模型独立 Reviewer 更有价值

### 为什么推送而非轮询

初版 Lead 用 `wait-for-idle.sh` 轮询 Coder 的提示符。问题：
- idle 检测误判（命令间隙被当作完成）
- Lead 反复轮询 + 汇报中间状态，浪费 token
- 社区主流方案（claude-squad、ccb）都依赖轮询，但体验不好

改为 Coder 完成后主动 `tmux-bridge message lead` 推送，Lead 派活后结束回合等消息。

### 为什么用通用 Skill 而非角色专用

- Lead 和 Coder 加载同一个 `skills/orchestra/SKILL.md`
- 通过 `$ORCH_ROLE` 环境变量区分角色
- 条件激活：非 orchestra 环境（$ORCH_ROLE 未设置）自动忽略
- 支持双向通信：Coder 也可以主动给 Lead 发消息

### Codex 沙箱处理

macOS 上 Codex 使用 Apple Seatbelt 沙箱，`network_access=true` 不生效（openai/codex#10390），AF_UNIX socket 连接被拒。

当前方案：`--sandbox danger-full-access -a on-request`
- `danger-full-access` 放开 OS 级限制（含 tmux socket）
- `-a on-request` 保留应用级审批（Codex 自行判断何时需确认，危险命令会拦截）

等 #10390 修复后可切回 socket 白名单方案。

## 通信协议

```
Lead → Coder:  tmux-bridge message coder "任务描述"
Coder → Lead:  tmux-bridge message lead "任务完成：概要"
```

推送模式。双向通信，任一方都可以主动发消息。

## 参考来源

- [smux (ShawnPana/smux)](https://github.com/ShawnPana/smux) — tmux-bridge 通信
- [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — API 模式替代方案
- [adversarial-review](https://github.com/alecnielsen/adversarial-review) — 跨模型互审实践
- [Addy Osmani - Code Agent Orchestra](https://addyosmani.com/blog/code-agent-orchestra/) — 多 agent 架构分析
- [Kaushik Gopal](https://kau.sh/blog/agent-forking/) — "A Bash script and tmux. That's it."
