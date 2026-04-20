# Architecture

## Key Decisions

**tmux over pipes** — persistent sessions, mature IPC (send-keys/capture-pane), human can switch panes anytime.

**smux over raw tmux** — `tmux-bridge read coder 100` saves tokens vs raw capture-pane. Read Guard prevents blind ops.

**Push over poll** — initial `wait-for-idle.sh` polling had false positives and wasted tokens. Now workers push via `tmux-bridge message`.

**2 agents over 3** — Reviewer removed. Codex `/review` + Claude `/simplify` covers it. Cross-model review is more valuable than same-model independent reviewer.

**Shared skill** — one `skills/orca/SKILL.md` for both roles. Role from `$ORCA_ROLE` env var (not activation command). Lead gets `$ORCA_WORKERS` (CSV), workers get `$ORCA_PEER` pointing to lead.

**Heartbeat via hooks** — no background monitor (deferred to P3). Workers write timestamps via PostToolUse hook (`.orca/heartbeat/<id>`). Lead checks heartbeats via PreToolUse hook, outputs `[orca]` notifications inline on next tool use. 30s cooldown per worker. Limitation: notifications only surface when lead is actively using tools.

**On-demand worktrees** — `orca-worktree create/remove/list/clean` at `.orca/worktree/<id>`. Created by lead before dispatch, cleaned by `orca stop`.

**Handoff files** — long-context dispatch uses `/tmp/orca-handoff-<slug>-<timestamp>.md` instead of inline tmux-bridge messages. Survives truncation, context compaction, and worker restarts.

**Codex sandbox** — macOS Seatbelt `network_access=true` broken for AF_UNIX (openai/codex#10390). Using `--sandbox danger-full-access -a on-request`. Waiting for fix.

**Codex activation** — startup: prompt parameter (auto). After /clear: monitor + user Enter (tmux can't send Enter to ratatui TUI, Kitty keyboard protocol).

## Install Side Effects

| Path | Action |
|------|--------|
| `~/.local/bin/orca, orca-worktree` | symlinks |
| `~/.claude/skills/orca, orca-code` | symlinks |
| `~/.agents/skills/orca, orca-code` | symlinks |
| `~/.claude/settings.json` | SessionStart + PostToolUse + PreToolUse hooks |
| `~/.smux/bin/` | install smux binary |

start.sh also sets per-session: `mode-keys vi`, `mouse on`, `bind-key Space even-horizontal`.

## Design Docs

- [Communication](design/communication.md) — tmux-bridge protocol, handoff files, multi-worker addressing
- [Multi-Worker](design/multi-worker.md) — model-agnostic architecture, worktree isolation, env vars
- [Heartbeat](design/heartbeat.md) — idle detection mechanism, tradeoffs, limitations

## References

- [smux](https://github.com/ShawnPana/smux) — tmux-bridge
- [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — API-mode alternative
- [adversarial-review](https://github.com/alecnielsen/adversarial-review) — cross-model review
- [Addy Osmani](https://addyosmani.com/blog/code-agent-orchestra/) — multi-agent analysis
- [Kaushik Gopal](https://kau.sh/blog/agent-forking/) — "A Bash script and tmux. That's it."
