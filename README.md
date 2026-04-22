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
orca                    # start (claude lead + codex worker)
orca stop               # stop
```

Talk to the lead (left pane): `Have the coder write a hello world script`

### Multi-Worker

```bash
orca --workers 3                           # 1 lead + 3 workers
orca --workers 3 --workflow code           # with code workflow
orca --lead claude --worker codex          # explicit models (default)
orca --worker ./my-agent                   # custom binary as worker
```

Workers get isolated git worktrees (`.orca/worktree/<slug>`) and heartbeat monitoring. Use a kebab-case feature slug such as `auth-refactor`; append `-<n>` only when multiple workers share the same feature.

See [design docs](docs/design/) for architecture details.

### Pane Shortcuts

Standard tmux bindings (prefix is `Ctrl+B`):

| Shortcut | Action |
|----------|--------|
| `prefix` then `z` | Toggle full-screen for the focused pane |
| `prefix` then `Space` | Re-even pane widths (orca rebinds to `even-horizontal`) |

## CLI

| Command | Description |
|---------|-------------|
| `orca [OPTIONS]` | Start or reattach |
| `orca stop` | Stop the current dir's instance |
| `orca ps` | List all running instances |
| `orca rm <name\|id>` | Remove a specific instance (any dir) |
| `orca prune` | Clean up dead socket inodes |
| `orca idle -t coder -T 300` | Wait for an agent pane to go idle |
| `orca-worktree create/remove/list/clean` | Manage worker worktrees (`<slug>` must be kebab-case) |
| `tmux-bridge read/message/list` | Cross-pane communication |

### Start Options

| Flag | Default | Description |
|------|---------|-------------|
| `-n, --workers N` | 1 | Number of worker panes |
| `--lead MODEL` | claude | Lead model (claude\|codex\|binary) |
| `--worker MODEL` | codex | Worker model (claude\|codex\|binary) |
| `-w, --workflow NAME` | - | Workflow skill (e.g. `code`) |

## Known Limitations

- **Codex macOS sandbox**: openai/codex#10390 — using `--sandbox danger-full-access -a on-request`
- **Shift+Enter in Codex (Ghostty + tmux)**: Codex 0.121 doesn't negotiate the Kitty keyboard protocol under tmux, so Ghostty's Shift+Enter doesn't reach it. Use Option+Enter for newline, or remap Shift+Enter in Ghostty config — see [docs/troubleshooting/ghostty-codex-shift-enter.md](docs/troubleshooting/ghostty-codex-shift-enter.md).
- **Cmd+Click links in Ghostty/Zed + tmux**: tmux `mouse on` consumes Cmd+Click before the terminal can turn it into a hyperlink jump. Use **Shift+Cmd+Click** instead, or switch to iTerm2/WezTerm — see [docs/troubleshooting/tmux-osc8-hyperlinks.md](docs/troubleshooting/tmux-osc8-hyperlinks.md).
- **iTerm2 mouse stops working in panes**: if clicks don't switch panes and the scroll wheel scrolls the whole window instead of one pane, open Settings → Profiles → *current profile* → Terminal and toggle **Enable mouse reporting** — check it if unchecked, or uncheck and re-check it if it already looks enabled (the runtime state can desync from the checkbox). Not an orca bug — happens in any tmux session.
- **Heartbeat is not real-time**: idle notifications surface on lead's next tool use, not instantly (see [docs/design/heartbeat.md](docs/design/heartbeat.md))

## License

MIT
