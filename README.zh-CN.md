# Orca

> **实验性项目，未准备好用于生产。**

多 agent 编排器。任意 agent CLI 做 lead/worker，tmux-bridge 通信，skill 驱动工作流。

[English](README.md) | 中文

```
用户 → Lead 派活 → Worker 编码 → /review 自查 → 汇报 Lead → /simplify 优化 → 汇报用户
         Claude        GPT          GPT             Claude
```

- **跨模型交叉把关** — GPT 写 + 自查，Claude 独立优化
- **双向通信** — Worker 可主动找 Lead 协商
- **推送不轮询** — Worker 完成后主动通知
- **实时可见** — 分屏观察，随时介入

## 安装

```bash
git clone https://github.com/fmfsaisai/orca.git
cd orca && ./install.sh
```

安装副作用详见 [ARCHITECTURE.md](docs/ARCHITECTURE.md#install-side-effects)。

## 快速开始

```bash
cd /path/to/your/project
orca                    # 启动（或重新 attach）
orca stop               # 停止
```

在 Lead pane（左侧）对话：`让 coder 写一个 hello world 脚本`

### 多 Worker

```bash
orca --workers 3                           # 1 lead + 3 workers
orca --workers 3 --workflow code           # 使用 code workflow
orca --lead claude --worker codex          # 指定模型（默认值）
orca --worker ./my-agent                   # 自定义 binary 做 worker
```

Worker 使用独立 git worktree（`.orca/worktree/<id>`）隔离，心跳机制监控 idle 状态。

架构详情见 [design docs](docs/design/)。

## 命令

| 命令 | 说明 |
|------|------|
| `orca [OPTIONS]` | 启动或重新 attach |
| `orca stop` | 停止当前目录的实例 |
| `orca ps` | 列出所有运行中的实例 |
| `orca rm <name\|id>` | 移除指定实例（任意目录） |
| `orca prune` | 清理失效的 socket inode |
| `orca idle -t coder -T 300` | 等待 agent pane 进入 idle |
| `orca-worktree create/remove/list/clean` | 管理 worker worktree |
| `tmux-bridge read/message/list` | 跨 pane 通信 |

### 启动选项

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-n, --workers N` | 1 | Worker pane 数量 |
| `--lead MODEL` | claude | Lead 模型（claude\|codex\|binary） |
| `--worker MODEL` | codex | Worker 模型（claude\|codex\|binary） |
| `-w, --workflow NAME` | - | Workflow skill（如 `code`） |

## 已知限制

- **Codex macOS 沙箱**：openai/codex#10390 — 使用 `--sandbox danger-full-access -a on-request`
- **Codex 内 Shift+Enter（Ghostty + tmux）**：Codex 0.121 在 tmux 下不协商 Kitty 键盘协议，Ghostty 的 Shift+Enter 编码到不了它。换行用 Option+Enter，或在 Ghostty config 里 remap Shift+Enter — 见 [docs/troubleshooting/ghostty-codex-shift-enter.md](docs/troubleshooting/ghostty-codex-shift-enter.md)。
- **Ghostty + tmux 内 Cmd+Click 跳转链接**：tmux `mouse on` 在 Ghostty 转成 hyperlink 跳转之前就消费了 Cmd+Click。改用 **Shift+Cmd+Click**，或换 Zed/iTerm2/WezTerm — 见 [docs/troubleshooting/tmux-osc8-hyperlinks.md](docs/troubleshooting/tmux-osc8-hyperlinks.md)。
- **心跳非实时**：idle 通知在 lead 下次 tool 调用时才显示，非即时推送（见 [docs/design/heartbeat.md](docs/design/heartbeat.md)）

## License

MIT
