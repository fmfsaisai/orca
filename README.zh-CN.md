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
orca-stop               # 停止
```

在 Lead pane（左侧）对话：`让 coder 写一个 hello world 脚本`

## 命令

| 命令 | 说明 |
|------|------|
| `orca` | 启动或重新 attach |
| `orca-stop` | 停止 session |
| `orca-idle -t coder -T 300` | 等待 idle（备用） |
| `tmux-bridge read/message/list` | 跨 pane 通信 |

## 已知限制

- **Codex macOS 沙箱**：openai/codex#10390 — 使用 `--sandbox danger-full-access -a on-request`
- **单 worker**：多 worker 计划中（见 [PLAN.md](PLAN.md)）

## License

MIT
