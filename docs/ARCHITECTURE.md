# Architecture

## Key Decisions

**tmux over pipes** — persistent sessions, mature IPC (send-keys/capture-pane), human can switch panes anytime.

**smux over raw tmux** — `tmux-bridge read coder 100` saves tokens vs raw capture-pane. Read Guard prevents blind ops.

**Push over poll** — initial `wait-for-idle.sh` polling had false positives and wasted tokens. Now workers push via `tmux-bridge message`.

**2 agents over 3** — Reviewer removed. Codex `/review` + Claude `/simplify` covers it. Cross-model review is more valuable than same-model independent reviewer.

**Shared skill** — one `skills/orca/SKILL.md` for both roles. Role by activation command (`/orca` = lead, `$orca` = worker). Dynamic peer via `$ORCA_PEER`.

**Codex sandbox** — macOS Seatbelt `network_access=true` broken for AF_UNIX (openai/codex#10390). Using `--sandbox danger-full-access -a on-request`. Waiting for fix.

**Codex activation** — startup: prompt parameter (auto). After /clear: monitor + user Enter (tmux can't send Enter to ratatui TUI, Kitty keyboard protocol).

## Install Side Effects

| Path | Action |
|------|--------|
| `~/.local/bin/orca, orca-stop, orca-idle` | symlink |
| `~/.claude/skills/orca` | symlink |
| `~/.agents/skills/orca` | symlink |
| `~/.claude/settings.json` | append SessionStart hook |
| `~/.codex/hooks.json` | create/append SessionStart hook |
| `~/.smux/bin/` | install smux binary |

start.sh also sets per-session: `mode-keys vi`, `mouse on`, `bind-key Space even-horizontal`.

## References

- [smux](https://github.com/ShawnPana/smux) — tmux-bridge
- [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — API-mode alternative
- [adversarial-review](https://github.com/alecnielsen/adversarial-review) — cross-model review
- [Addy Osmani](https://addyosmani.com/blog/code-agent-orchestra/) — multi-agent analysis
- [Kaushik Gopal](https://kau.sh/blog/agent-forking/) — "A Bash script and tmux. That's it."
