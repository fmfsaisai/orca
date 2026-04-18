# Orca

> **实验性项目，未准备好用于生产。**

模型无关的多 agent 编排器。任意模型做 lead/worker，tmux-bridge 通信，skill 驱动工作流。

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

## 使用

```bash
cd /path/to/your/project
orca                    # 启动（或重新 attach）
orca stop               # 停止
```

在 Lead pane（左侧）对话：`让 coder 写一个 hello world 脚本`

## 命令

| 命令 | 说明 |
|------|------|
| `orca` | 启动或重新 attach（claude lead + codex worker） |
| `orca stop` | 停止当前目录的实例 |
| `orca ps` | 列出所有运行中的实例 |
| `orca rm <name\|id>` | 移除指定实例（任意目录） |
| `orca prune` | 清理失效的 socket inode |
| `orca idle -t coder -T 300` | 等待 agent pane 进入 idle |
| `tmux-bridge read/message/list` | 跨 pane 通信 |

## 已知限制

- **Codex macOS 沙箱**：openai/codex#10390 — 使用 `--sandbox danger-full-access -a on-request`
- **Codex 内 Shift+Enter（Ghostty + tmux）**：Codex 0.121 在 tmux 下不协商 Kitty 键盘协议，Ghostty 的 Shift+Enter 编码到不了它。换行用 Option+Enter，或在 Ghostty config 里 remap Shift+Enter — 见 [docs/troubleshooting/ghostty-codex-shift-enter.md](docs/troubleshooting/ghostty-codex-shift-enter.md)。
- **Ghostty + tmux 内 Cmd+Click 跳转链接**：tmux `mouse on` 在 Ghostty 转成 hyperlink 跳转之前就消费了 Cmd+Click。改用 **Shift+Cmd+Click**，或换 Zed/iTerm2/WezTerm — 见 [docs/troubleshooting/tmux-osc8-hyperlinks.md](docs/troubleshooting/tmux-osc8-hyperlinks.md)。
- **单 worker**：多 worker 计划中（见 [PLAN.md](PLAN.md)）

## License

MIT
