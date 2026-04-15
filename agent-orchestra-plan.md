# Agent Orchestra 实施规划

## 目标

个人开发者日常多 agent 协同方案。Lead (Claude Code) 调度 Coder (Codex CLI)，两者在同一 tmux session 的不同 pane 中工作，实时可见。

## 技术栈

| 组件 | 用途 | 状态 |
|------|------|------|
| tmux 3.6a | 终端复用、分屏、pane 管理 | 已安装 |
| smux / tmux-bridge 2.0.0 | pane 间通信原语 | 已安装 |
| Claude Code CLI | Lead 角色（调度 + /simplify 独立优化） | 已安装 |
| Codex CLI 0.114.0 | Coder 角色（编码 + /review 自查） | 已安装 |

## 架构

```
┌──────────────┬──────────────┐
│              │              │
│  Lead        │  Coder       │
│  (Claude)    │  (Codex)     │
│  调度+优化    │  编码+自查    │
│              │              │
└──────────────┴──────────────┘
       tmux session: orchestra
```

流水线：用户 → Lead 派活 → Coder 编码 → /review 自查修复 → tmux-bridge 汇报 Lead → Lead /simplify 独立优化 → 向用户汇报

## 项目结构

```
~/agent-orchestra/
├── agent-orchestra-plan.md         # 本文件：实施规划与进度
├── README.md                      # 使用指南
├── start.sh                       # 启动脚本（orch）
├── stop.sh                        # 停止脚本（orch-stop）
├── wait-for-idle.sh               # idle 检测脚本（orch-idle，备用）
├── skills/orchestra/SKILL.md      # 通用 Skill（Lead + Coder 共用）
└── docs/ARCHITECTURE.md           # 架构决策记录
```

全局命令（~/.local/bin/ 软链）：`orch`、`orch-stop`、`orch-idle`

## 实施步骤与进度

### Phase 1: 项目搭建

- [x] 创建目录结构
- [x] 编写 `docs/ARCHITECTURE.md`
- [x] 编写 `README.md`

### Phase 2: 核心脚本

- [x] 编写 `start.sh` — tmux session 创建、分屏布局、agent 启动、pane 命名
- [x] 编写 `stop.sh` — session 清理（带确认）
- [x] 编写 `wait-for-idle.sh` — 轮询 capture-pane 检测提示符，支持 label 解析、超时、ANSI 清理、连续稳定检测
- [x] Review: 修复 macOS BSD sed/grep 兼容性
- [x] Review: 收紧 idle 检测正则，适配 Codex 实际提示符（`Find and fix a bug`）

### Phase 3: Skill

- [x] 编写 `skills/orchestra/SKILL.md` — 初版 Lead 专用 Skill
- [x] 重构为通用 Skill — Lead + Coder 共用，角色由 agent 类型固定（Claude Code = lead，Codex = coder）
- [x] 加入条件激活：`$ORCH` 环境变量 + SessionStart hook 自动激活
- [x] 加入 YAML frontmatter（兼容 Codex 加载）
- [x] 架构演进：3 agent（Lead+Coder+Reviewer）→ 2 agent（Lead+Coder）
  - Coder: 编码 → /review 自查修复
  - Lead: /simplify 独立优化（跨模型 GPT+Claude 交叉把关）
- [x] 通信模式演进：Lead 轮询 → Coder 主动推送（tmux-bridge message lead）
- [x] 禁止 Lead 环境验证（orch 脚本保证就绪）
- [x] 禁止 Lead 等待期间轮询/汇报中间状态

### Phase 4: 安装与集成

- [x] 安装 smux — tmux-bridge 2.0.0
- [x] 验证 tmux-bridge 命令格式与 start.sh 兼容
- [x] 建立 Skill 软链：`~/.claude/skills/orchestra → ~/.agents/skills/orchestra → 项目 skills/orchestra`
- [x] start.sh 注入 `ORCH` + `ORCH_PEER` 环境变量
- [x] start.sh 自动 attach + 自动启动 Lead/Coder
- [x] Claude Code: SessionStart hook + nohup 自动发送 `/orchestra`（new session 也生效）
- [x] Codex: start.sh prefill `$orchestra` 到输入框（用户手动回车确认）
- [x] Codex: hooks.json 已配置但 v0.120.0 hooks 功能未生效，等版本更新
- [x] 脚本全局化：`orch`/`orch-stop`/`orch-idle` 软链到 `~/.local/bin/`
- [x] Codex 沙箱配置：`--sandbox danger-full-access`（macOS Seatbelt 已知 bug #10390 导致 network_access=true 无效）

### Phase 5: 端到端验证

- [x] 运行 `orch`，确认两分屏布局正确
- [x] 确认 Lead (Claude) 和 Coder (Codex) 正常启动
- [x] 测试 tmux-bridge 通信（Lead → Coder 派活）
- [x] 测试 Coder 执行任务并产出结果
- [ ] 测试 Coder 完成后通过 tmux-bridge 主动汇报 Lead
- [ ] 测试 Lead 收到汇报后执行 /simplify
- [ ] 测试完整流水线：派活 → 编码 → /review → 汇报 → /simplify → 用户汇报
- [x] 运行 `orch-stop` 清理

### Phase 6: 迭代优化（按需）

- [x] SessionStart hook 自动激活：$ORCH 环境变量 + hook 取代 sleep hack 和手动 /orchestra
- [x] ORCH_ROLE 简化为 ORCH：角色由 agent 类型固定，不再需要环境变量区分
- [x] 强化禁止轮询规则：逐条列出禁止命令，堵死"看一眼"的空子
- [x] coder 默认自测：/review（自查）和构建+测试（自测）分离，都是默认必做
- [x] handoff 机制：大型任务 / plan mode 传递用 .agents/handoff/ 临时交接文档
- [x] 多实例隔离：pane label 加 session 前缀（`${SESSION}-lead`/`${SESSION}-coder`），ORCH_PEER 环境变量动态配对
- [x] SKILL.md 通信目标动态化：硬编码 `coder`/`lead` → `$ORCH_PEER`
- [x] Claude Code hook 精确触发：SessionStart + nohup + tmux send-keys 走 Skill 加载路径
- [ ] 等 Codex hooks 功能生效后启用 coder 侧 new session 自动激活
- [ ] 考虑是否需要日志记录（agent 间通信历史）
- [ ] 考虑是否需要 worktree 隔离（多 coder 并行场景）
- [ ] 考虑双 reviewer 扩展（Claude + Codex 并行 review，四分屏）
- [ ] 等 Codex #10390 修复后切回 socket 白名单方案

## Skill 注册方式

```
~/.claude/skills/orchestra → ~/.agents/skills/orchestra → ~/agent-orchestra/skills/orchestra
```

项目 skills/ 目录下的 SKILL.md 同时被 Claude Code（通过 ~/.claude/skills/ 软链）和 Codex（通过项目目录扫描）加载。

## 架构决策摘要

详见 `docs/ARCHITECTURE.md`。核心决策：

- **tmux 作为 IPC**：成熟、持久、可人工接管
- **smux 包装**：省 token、语义清晰
- **推送模式**：Coder 完成后主动 message Lead，而非 Lead 轮询（社区主流是轮询，我们的方案更干净）
- **跨模型交叉把关**：Coder (GPT) /review 自查 + Lead (Claude) /simplify 独立优化
- **纯脚本方案**：不写 Go/Rust/Python 服务，Shell + Skill 足矣
- **2 agent 架构**：Lead + Coder，不需要独立 Reviewer（/review + /simplify 已覆盖）
- **多实例隔离**：pane label 带 session 前缀 + ORCH_PEER 环境变量，避免多 orch 实例通信串台
- **Skill 自动激活**：Claude Code 用 SessionStart hook + nohup send-keys 走命令解析器；Codex hooks 未生效，用 start.sh prefill 兜底
