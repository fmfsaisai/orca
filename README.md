# Orca

> **Claude 调度，Codex 编码，跨模型交叉把关。一条命令启动，tmux 实时可见。**

```
┌─ lead ─────────────────────┬─ coder ────────────────────┐
│ › 让 coder 写个 sysinfo 脚本│                            │
│                            │ Coder 已就绪，等待 Lead 派活。│
│ ● Skill(orca)              │                            │
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
│ › _                        │                            │
├────────────────────────────┴────────────────────────────┤
│ 0:main                                                  │
└─────────────────────────────────────────────────────────┘
```

```
用户 → Lead 派活 → Coder 编码 → /review 自查 → 汇报 Lead → /simplify 优化 → 汇报用户
         Claude        GPT          GPT             Claude
```

**Coder 也能主动找 Lead 协商：**

```
┌─ lead ─────────────────────┬─ coder ────────────────────┐
│                            │ 分析完需求，我建议的         │
│                            │ plan 范围：                 │
│                            │ - seed 目录结构和模板        │
│                            │ - manifest/hash 校验        │
│                            │ - runtime mount 边界        │
│                            │                            │
│                            │ 发给 lead 看看...            │
│                            │                            │
│                            │ ● tmux-bridge message lead  │
│                            │   "建议 plan 范围：..."      │
│                            │                            │
│ ● tmux-bridge from:coder   │                            │
│   "建议 plan 范围：         │                            │
│    seed 模板/manifest 校验/ │                            │
│    runtime mount 边界"     │                            │
│                            │                            │
│ 收到 coder 的方案建议。      │ › _                        │
│ 我来评估一下...              │                            │
│                            │                            │
│ › _                        │                            │
├────────────────────────────┴────────────────────────────┤
│ 0:main                                                  │
└─────────────────────────────────────────────────────────┘
```

- **跨模型交叉把关** — GPT 写代码 + 自查，Claude 独立优化，盲区互补
- **双向通信** — Coder 可以主动找 Lead 协商方案、请求确认，不是单向派活
- **人在回路** — 实时观察两个 agent 工作，随时切 pane 手动介入
- **推送不轮询** — Coder 完成后主动通知 Lead，不烧 token 空转
- **零配置启动** — `orca` 一条命令，按目录自动隔离 session

## 安装

### 前置条件

- macOS 或 Linux
- [tmux](https://github.com/tmux/tmux) >= 3.0（macOS: `brew install tmux`）
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [Codex CLI](https://github.com/openai/codex)（`npm install -g @openai/codex`）

### 一键安装

```bash
git clone https://github.com/fmfsaisai/orca.git
cd orca
./install.sh
```

### install.sh 会修改的文件

安装脚本会写入以下位置，卸载时需手动清理：

| 路径 | 操作 | 作用 |
|------|------|------|
| `~/.local/bin/orca, orca-stop, orca-idle` | 创建符号链接 | 全局命令 |
| `~/.claude/skills/orca` | 创建符号链接 | Claude Code Skill 注册 |
| `~/.agents/skills/orca` | 创建符号链接 | Codex Skill 注册 |
| `~/.claude/settings.json` | 追加 `hooks.SessionStart` | Lead 新会话自动激活 Skill |
| `~/.codex/hooks.json` | 创建文件，写入 `hooks.SessionStart` | Coder 新会话提示激活 Skill |
| `~/.smux/bin/` | 安装 smux 二进制 | 提供 tmux-bridge CLI |
| `~/.zshrc` 或 `~/.bash_profile` | 追加一行 PATH | 将 smux 加入 PATH |

启动时 `start.sh` 还会设置 tmux 配置：

| 配置 | 作用 | 范围 |
|------|------|------|
| `mode-keys vi` | ESC 退出 search/copy mode | 仅 orca session |
| `mouse on` | 鼠标点击切换 pane | 仅 orca session |
| `bind-key Space select-layout even-horizontal` | `Ctrl+B Space` 恢复等宽布局 | 全局（tmux 限制） |

### 手动安装

```bash
# 1. 安装 smux（提供 tmux-bridge CLI）
curl -fsSL https://shawnpana.com/smux/install.sh | bash

# 2. 确保 smux 在 PATH 中（安装脚本会写入 ~/.bashrc，macOS 用户可能需要）
echo 'export PATH="$HOME/.smux/bin:$PATH"' >> ~/.bash_profile

# 3. 给脚本加执行权限
chmod +x ~/orca/*.sh

# 4. 创建全局命令
ln -sf ~/orca/start.sh ~/.local/bin/orca
ln -sf ~/orca/stop.sh ~/.local/bin/orca-stop
ln -sf ~/orca/wait-for-idle.sh ~/.local/bin/orca-idle

# 5. 注册 Skill 到 Claude Code
mkdir -p ~/.claude/skills
ln -sf ~/orca/skills/orca ~/.claude/skills/orca
```

## 使用

### 启动

```bash
cd /path/to/your/project
orca              # 在当前目录启动
```

自动创建 tmux session（名称基于目录名，如 `orca-my-project`），启动 Lead + Coder，直接进入分屏。

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
orca-stop         # 停止当前目录的 orca session
```

或在 tmux 内按 `Ctrl+B D` 暂时脱离（session 后台运行），再次 `orca` 重新附加。

### 等宽布局

窗口大小变化后，按 `Ctrl+B Space` 恢复等宽。

## 命令速查

| 命令 | 作用 |
|------|------|
| `orca` | 启动/附加 orca session |
| `orca-stop` | 停止 orca session |
| `orca-idle -t coder -T 300` | 等待 coder idle（备用，一般不需要） |
| `tmux-bridge list` | 查看所有 pane |
| `tmux-bridge read coder 100` | 读取 coder 最近 100 行 |
| `tmux-bridge message coder "..."` | 给 coder 发消息 |

## 文件说明

| 文件 | 作用 |
|------|------|
| `start.sh` | 创建 tmux session + 分屏 + 启动 agents + skill 自动激活 + /clear monitor |
| `stop.sh` | 停止并清理 tmux session + monitor 进程 |
| `install.sh` | 一键安装（smux + 全局命令 + Skill 注册 + SessionStart hooks） |
| `wait-for-idle.sh` | idle 检测（备用，主流程不依赖） |
| `skills/orca/SKILL.md` | 通用 Skill（Lead + Coder 共用，角色由激活命令决定） |
| `docs/ARCHITECTURE.md` | 架构决策记录 |

## 架构要点

- **tmux 作为 IPC**：成熟、持久、可人工接管，断网重连 session 还在
- **推送模式**：Coder 完成后主动 message Lead，不轮询
- **跨模型交叉把关**：Coder (GPT) /review 自查 + Lead (Claude) /simplify 独立优化
- **通用 Skill**：Lead 和 Coder 加载同一个 SKILL.md，角色由激活命令决定（`/orca` = Lead，`$orca` = Coder）
- **自动激活**：Lead 通过 SessionStart hook 自动加载 Skill；Coder 启动时通过 prompt 参数自动激活，`/clear` 后由 monitor 重新激活
- **按目录隔离**：不同项目目录的 session 互不干扰

## 已知限制

- **Codex macOS 沙箱**：macOS 上 Codex 的 socket 白名单不生效（openai/codex#10390），需要 `--sandbox danger-full-access`。`-a on-request` 保证危险命令仍需确认
- **Codex /clear 后需手动确认**：`/clear` 后 monitor 会自动输入 `$orca`，但因 tmux 无法向 Codex ratatui TUI 发送 Enter（Kitty 键盘协议限制），需要用户手动按 Enter 确认
- **idle 检测**：`wait-for-idle.sh` 作为备用工具保留，主流程依赖 Coder 主动汇报

## 替代方案对比

| 方案 | 优势 | 劣势 |
|------|------|------|
| **orca (本项目)** | 实时可见、可手动介入、跨模型 | 需要 tmux 基础、Codex 沙箱 hack |
| [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) | 无沙箱问题、API 直连 | 后台运行不可见、不能中途介入 |
| [claude-squad](https://github.com/smtg-ai/claude-squad) | 成熟的会话管理 | 无 agent 间通信、不适合流水线 |
| [Claude Agent Teams](https://docs.anthropic.com/en/docs/agent-teams) | 官方支持 | 实验性、不支持混搭 Codex |
