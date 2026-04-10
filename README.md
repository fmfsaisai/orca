# Agent Orchestra

> **Claude 调度，Codex 编码，跨模型交叉把关。一条命令启动，tmux 实时可见。**

```
┌─ lead ─────────────────────┬─ coder ────────────────────┐
│ > 让 coder 写个 sysinfo 脚本│ › echo $ORCH_ROLE          │
│                            │ coder                      │
│ ● Skill(orchestra)         │                            │
│   Successfully loaded      │ 收到任务，开始实现...         │
│                            │ Created sysinfo.sh (312行)  │
│ 已派活给 coder，等待汇报。    │                            │
│                            │ ● Ran /review              │
│                            │   发现 2 个问题，已修复      │
│                            │                            │
│                            │ ● tmux-bridge message lead  │
│                            │   "完成，修改 1 个文件"      │
│                            │                            │
│ 收到 coder 汇报。           │ › _                        │
│                            │                            │
│ ● Ran /simplify            │                            │
│   优化了 3 处代码复用        │                            │
│   修复了 1 处性能问题        │                            │
│                            │                            │
│ 任务完成汇报：              │                            │
│ - sysinfo.sh 已创建 (312行) │                            │
│ - Coder /review 修复 2 处   │                            │
│ - /simplify 优化 4 处       │                            │
│ - 已设置可执行权限           │                            │
│                            │                            │
│ > _                        │                            │
├────────────────────────────┴────────────────────────────┤
│ 0:main                                                  │
└─────────────────────────────────────────────────────────┘
```

```
用户 → Lead 派活 → Coder 编码 → /review 自查 → 汇报 Lead → /simplify 优化 → 汇报用户
         Claude        GPT          GPT             Claude
```

- **跨模型交叉把关** — GPT 写代码 + 自查，Claude 独立优化，盲区互补
- **人在回路** — 实时观察两个 agent 工作，随时切 pane 手动介入或调整方向
- **推送不轮询** — Coder 完成后主动通知 Lead，不烧 token 空转
- **零配置启动** — `orch` 一条命令，按目录自动隔离 session

## 安装

### 前置条件

- macOS 或 Linux
- [tmux](https://github.com/tmux/tmux) >= 3.0（macOS: `brew install tmux`）
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [Codex CLI](https://github.com/openai/codex)（`npm install -g @openai/codex`）

### 一键安装

```bash
# 解压或克隆到任意位置
cd ~/agent-orchestra
./install.sh
```

### 手动安装

```bash
# 1. 安装 smux（提供 tmux-bridge CLI）
curl -fsSL https://shawnpana.com/smux/install.sh | bash

# 2. 确保 smux 在 PATH 中（安装脚本会写入 ~/.bashrc，macOS 用户可能需要）
echo 'export PATH="$HOME/.smux/bin:$PATH"' >> ~/.bash_profile

# 3. 给脚本加执行权限
chmod +x ~/agent-orchestra/*.sh

# 4. 创建全局命令
ln -sf ~/agent-orchestra/start.sh ~/.local/bin/orch
ln -sf ~/agent-orchestra/stop.sh ~/.local/bin/orch-stop
ln -sf ~/agent-orchestra/wait-for-idle.sh ~/.local/bin/orch-idle

# 5. 注册 Skill 到 Claude Code
mkdir -p ~/.claude/skills
ln -sf ~/agent-orchestra/skills/orchestra ~/.claude/skills/orchestra
```

## 使用

### 启动

```bash
cd /path/to/your/project
orch              # 在当前目录启动 orchestra
```

自动创建 tmux session（名称基于目录名，如 `orch-my-project`），启动 Lead + Coder，直接进入分屏。

### 工作

在 Lead pane（左侧）正常对话即可：

```
让 coder 写一个 hello world 脚本
```

Lead 会自动：
1. 跟你确认任务拆解
2. 通过 tmux-bridge 派活给 Coder
3. 等待 Coder 完成并汇报
4. 执行 /simplify 独立优化
5. 向你汇报最终结果

### 手动与 Coder 交互

点击右侧 Coder pane 可直接与 Codex 对话。Coder 也可以主动给 Lead 发消息。

### 停止

```bash
cd /path/to/your/project
orch-stop         # 停止当前目录的 orchestra session
```

或在 tmux 内按 `Ctrl+B D` 暂时脱离（session 后台运行），再次 `orch` 重新附加。

### 等宽布局

窗口大小变化后，按 `Ctrl+B Space` 恢复等宽。

## 命令速查

| 命令 | 作用 |
|------|------|
| `orch` | 启动/附加 orchestra session |
| `orch-stop` | 停止 orchestra session |
| `orch-idle -t coder -T 300` | 等待 coder idle（备用，一般不需要） |
| `tmux-bridge list` | 查看所有 pane |
| `tmux-bridge read coder 100` | 读取 coder 最近 100 行 |
| `tmux-bridge message coder "..."` | 给 coder 发消息 |

## 文件说明

| 文件 | 作用 |
|------|------|
| `start.sh` | 创建 tmux session + 分屏 + 启动 agents + 自动初始化 |
| `stop.sh` | 停止并清理 tmux session |
| `install.sh` | 一键安装（smux + 全局命令 + Skill 注册） |
| `wait-for-idle.sh` | idle 检测（备用，主流程不依赖） |
| `skills/orchestra/SKILL.md` | 通用 Skill（Lead + Coder 共用） |
| `docs/ARCHITECTURE.md` | 架构决策记录 |

## 架构要点

- **tmux 作为 IPC**：成熟、持久、可人工接管，断网重连 session 还在
- **推送模式**：Coder 完成后主动 message Lead，不轮询
- **跨模型交叉把关**：Coder (GPT) /review 自查 + Lead (Claude) /simplify 独立优化
- **通用 Skill**：Lead 和 Coder 加载同一个 SKILL.md，通过 `$ORCH_ROLE` 环境变量区分角色
- **按目录隔离**：不同项目目录的 session 互不干扰

## 已知限制

- **Codex macOS 沙箱**：macOS 上 Codex 的 socket 白名单不生效（openai/codex#10390），需要 `--sandbox danger-full-access`。`-a on-request` 保证危险命令仍需确认
- **初始化时序**：Coder 启动较慢，初始化消息延迟 8 秒发送，极慢网络下可能不够
- **idle 检测**：`wait-for-idle.sh` 作为备用工具保留，主流程依赖 Coder 主动汇报

## 替代方案对比

| 方案 | 优势 | 劣势 |
|------|------|------|
| **agent-orchestra (本项目)** | 实时可见、可手动介入、跨模型 | 需要 tmux 基础、Codex 沙箱 hack |
| [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) | 无沙箱问题、API 直连 | 后台运行不可见、不能中途介入 |
| [claude-squad](https://github.com/smtg-ai/claude-squad) | 成熟的会话管理 | 无 agent 间通信、不适合流水线 |
| [Claude Agent Teams](https://docs.anthropic.com/en/docs/agent-teams) | 官方支持 | 实验性、不支持混搭 Codex |
