# Orca

> **Experimental. NOT production-ready.**

Model-agnostic multi-agent orchestrator. Any model as lead or worker, tmux-bridge communication, skill-driven workflows.

[中文](README.zh-CN.md) | English

```
User → Lead dispatches → Worker codes → /review self-check → report Lead → /simplify optimize → report User
         Claude              GPT           GPT                    Claude
```

- **Mixed models** — Claude + GPT (or any combination), not locked to one model
- **Cross-model review** — GPT writes + self-reviews, Claude independently optimizes
- **Bidirectional** — Workers can propose plans to lead, not just receive orders
- **Push, not poll** — Workers notify lead on completion. No token-burning loops
- **Visible** — Real-time split panes. Intervene anytime

## Install

```bash
git clone https://github.com/fmfsaisai/orca.git
cd orca && ./install.sh
```

See [install.sh side effects](docs/ARCHITECTURE.md#install-side-effects) for what gets written to your system.

## Quick Start

```bash
cd /path/to/your/project
orca                    # start (or reattach)
orca stop               # stop
```

Talk to the lead (left pane): `Have the coder write a hello world script`

## CLI

| Command | Description |
|---------|-------------|
| `orca` | Start or reattach (default coder: codex) |
| `orca claude` | Start with claude as worker |
| `orca stop` | Stop the current dir's instance |
| `orca ps` | List all running instances |
| `orca rm <name\|id>` | Remove a specific instance (any dir) |
| `orca prune` | Clean up dead socket inodes |
| `orca idle -t coder -T 300` | Wait for an agent pane to go idle |
| `tmux-bridge read/message/list` | Cross-pane communication |

## Known Limitations

- **Codex macOS sandbox**: openai/codex#10390 — using `--sandbox danger-full-access -a on-request`
- **Shift+Enter in Codex (Ghostty + tmux)**: Codex 0.121 doesn't negotiate the Kitty keyboard protocol under tmux, so Ghostty's Shift+Enter doesn't reach it. Use Option+Enter for newline, or remap Shift+Enter in Ghostty config — see [docs/troubleshooting/ghostty-codex-shift-enter.md](docs/troubleshooting/ghostty-codex-shift-enter.md).
- **Single worker**: Multi-worker planned (see [PLAN.md](PLAN.md))

## License

MIT
