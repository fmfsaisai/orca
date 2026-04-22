# Orca Plan

## Vision

Model-agnostic multi-agent orchestrator. Any model combination as lead/worker. tmux-bridge + skills.

Differentiator: **mixed models + configurable roles + preset workflows**.

Inspired by [oh-my-claudecode](https://github.com/anthropics/oh-my-claudecode) (multi-agent workflow, heartbeat/idle detection) and [oh-my-codex](https://github.com/openai/codex) (Codex hooks automation). Orca adds model-agnostic orchestration on top.

## User Feedback (2026-04 churn signal)

Sourced from Nick's 2026-04-21 conversation. Pain → design constraint mapping; full transcript notes are out of scope. These motivate **Phase E0/E1/E2** below.

| # | Pain | Ask |
|---|---|---|
| 1 | Entry inverted — must run `orca` CLI before opening cc/codex | In-Agent entry: open cc, then `/orca dispatch ...` |
| 2 | tmux is forced; nested cc-in-tmux re-triggers another tmux | tmux on-demand only; nesting guard |
| 3 | Default 1 lead + N worker panes feels heavy ("打破幻想了") | Default single pane; spawn workers when concurrency is asked for |
| 4 | Hooks always-active feels intrusive | Hooks register but stay dormant until `/orca` activates |
| 5 | Worker走偏时跳进 worker pane 抢键盘（lead 转发延迟太高） | Lead-mediated intervention as 1st-class; cut comm latency |
| 6 | `orca ps` is shell-side only; useless inside cc | Expose `orca ps`/`clean` to cc as skill-callable |

Severity: 1/2/3 = P0 (caused churn); 4/5 = P1; 6 = P2. Detailed competitor parity analysis: [`docs/research/competitors.md`](docs/research/competitors.md).

## Done

Baseline orchestrator works end-to-end. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how. Highlights:

- tmux session + lead/worker panes, spawned via `orca` CLI; `start.sh --workers N --lead M --worker M --workflow code`
- tmux-bridge push communication with Read Guard (D10 message-body rule)
- Shared `skills/orca/SKILL.md` with role from `$ORCA_ROLE`; `code` workflow skill (`skills/workflows/code/SKILL.md`)
- On-demand worktrees (`orca-worktree create/remove/list/clean`); auto-append `.orca/` to host `.gitignore` on create
- Hooks: PostToolUse worker heartbeat + PreToolUse lead idle check
- Subcommands: `orca {stop,idle,ps,rm,prune}`; multi-instance per-dir naming (`orca-<dir>-<YYYYMMDDhhmmss>`) + TUI picker at start (PR #16)
- Per-instance dedicated tmux server (`tmux -L orca-<dirname>`) for env isolation

Validation gap: full e2e smoke test (dispatch → code → /review → report → /simplify) is tracked in [issue #28](https://github.com/fmfsaisai/orca/issues/28).

Known runtime limitations:
- Codex /clear needs 2× Enter (tmux can't send Enter to ratatui TUI under Kitty keyboard protocol)
- Codex sandbox workaround active (openai/codex#10390)

## Decisions

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| D1 | Worker completion notification | Heartbeat + state transition + cooldown | PostToolUse every call too noisy; pure skill text unreliable; borrowed from OMC |
| D2 | Multi-worker merge order | Lead decides per workflow | refactor=dependency order, code=first-done-first-merge |
| D3 | Mixed worker hooks | Each uses native hooks, Skill + tmux-bridge is the unified layer | CC hooks ≠ Codex hooks.json, but hook scripts shared |
| D4 | Workflow skill style | Hybrid: fixed checkpoints + principles between (light process) | Inspired by OMC's layered approach |
| D5 | Worktree timing | On-demand at dispatch time | User may need only 1 worker |
| D6 | Task dependencies | A — pure lead judgment, no `.orca/tasks/` files | Started as "B then simplify to A"; lead handling proved sufficient in practice. No tracking files to maintain. |
| D7 | Multi-instance per dir | `orca-<dir>-<YYYYMMDDhhmmss>` suffix + TUI picker at start | Resolved in PR #16. Legacy `orca-<dir>` (pre-feature) still recognized as a valid first instance. |
| D8 | tmux server scope | Per-instance dedicated server via `tmux -L orca-<dirname>` | User's main tmux server caches stale env globally; sharing it pollutes user state. Per-instance: stop=kill server=clean env. ~5MB overhead/instance. See [docs/troubleshooting/tmux-server-stale-env.md](docs/troubleshooting/tmux-server-stale-env.md) |
| D9 | Lead/worker model selection | `--lead MODEL --worker MODEL` flags + `$ORCA_ROLE` env var | Role-by-env-var decouples role from activation command. Any binary can be lead or worker. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#multi-worker). |
| D10 | Structured content delivery channel | Inline single-quoted `tmux-bridge message` is the default; switch to file on disk (`/tmp/orca-msg-*.md`) only when content contains `'` or newlines | `tmux load-buffer + paste-buffer` (Tier 1) tested but Codex multi-line paste needs Enter×2 (timing-sensitive) and full body lands in worker conversation history (compaction risk). Single-quote covers most short messages safely; file fallback only on `'` or newlines. File delivery keeps worker context lean (path-only message), is auditable, uses one mental model. Smux upstream so no code-level guard; rule enforced by SKILL discipline. |
| D11 | Entry surface + dispatch runtime | Host agent (cc/codex) owns orchestration via `/orca <task>` skill; `orca` CLI shrinks to shell utilities + conventions (`tmux-bridge`, `orca-worktree`, `orca {ps, stop, doctor, hud}`), no more `start.sh` fixed-layout launcher. Per-call resolution into three modes: **inline** (host runs task itself), **subagent** (host spawns child via cc Task tool), **pane** (real `cc`/`codex` process in tmux pane). Pane-needed-but-no-tmux degrades to subagent with one-line user-visible log (lose visibility, keep parallelism). Workflow ("implement → /review → test → report") hardcoded into `/orca`; future workflows ship as new slash commands (OMC `/autopilot` pattern). No backward-compat with `$ORCA_ROLE`/SessionStart auto-fire/heartbeat hooks — early enough to break, ship as one PR. | Triggered by [User Feedback](#user-feedback-2026-04-churn-signal) #1-3. Mechanics: [`docs/design/dispatch-runtime.md`](docs/design/dispatch-runtime.md). Competitor parity: [`docs/research/competitors.md`](docs/research/competitors.md). |

## Target Architecture

```
orca --lead claude --worker codex --workers 3 --workflow code

┌─ lead (claude) ──────┬─ w1 (codex) ─┬─ w2 (codex) ─┬─ w3 (codex) ─┐
│ dispatch + optimize  │ worktree/w1  │ worktree/w2  │ worktree/w3  │
│ Skill: lead          │ Skill: worker│ Skill: worker│ Skill: worker│
│ tmux-bridge          │ hooks + tmux │ hooks + tmux │ hooks + tmux │
└──────────────────────┴──────────────┴──────────────┴──────────────┘
```

## Roadmap

Three phases. Each phase is one GitHub epic; sub-tasks live in the epic's checklist.

### Phase E0 — Entry Refactor — [#25](https://github.com/fmfsaisai/orca/issues/25)

cc/codex user opens their agent normally and types `/orca <task>`. tmux/multi-pane only appear when parallelism is asked for and tmux is available. Resolves [User Feedback](#user-feedback-2026-04-churn-signal) #1-3 (and structurally enables #4). Per D11 this is a clean redesign — legacy `start.sh` / `$ORCA_ROLE` / SessionStart auto-fire / heartbeat hooks all go away. **Single PR.**

Scope (all in one PR — breaking happens once):

- Rewrite `skills/orca/SKILL.md` (resolution rules + per-mode instructions; embeds workflow text from `skills/workflows/code/`)
- Delete `skills/workflows/code/` (folded in)
- Add pane-spawn helper (extracted from `start.sh`)
- Add `orca doctor` subcommand
- Update `install.sh`: remove hook installs, drop the workflows symlink, add `orca doctor` invocation, update post-install message
- Delete `start.sh`
- Delete heartbeat hook entries from `~/.claude/settings.json`
- Update README quick-start (no more `orca` launcher; use `/orca <task>`)

Per-call mechanics, mode resolution, full removed-legacy list, open questions: [`docs/design/dispatch-runtime.md`](docs/design/dispatch-runtime.md).

### Phase E1 — Communication Continuity — [#26](https://github.com/fmfsaisai/orca/issues/26)

Lead↔worker is event-driven, not 5s-poll-driven. Resolves Pain #5. Subsumes the legacy "Worker Lifecycle" bucket (background heartbeat, timeout/retry, comm logs). Borrowing surface: OMX queue + claim model — see [`docs/research/competitors.md → OMX`](docs/research/competitors.md#omx--oh-my-codex).

### Phase E2 — Context Persistence — [#27](https://github.com/fmfsaisai/orca/issues/27)

Cross-session context recovery. Borrowing surface: ctx's workstream/session/entry SQLite model — see [`docs/research/competitors.md → ctx`](docs/research/competitors.md#ctx--local-context-persistence). Hard stop: shell + sqlite3 only.

### Standalone open work

- [#28](https://github.com/fmfsaisai/orca/issues/28) — Validate full pipeline e2e
- [#29](https://github.com/fmfsaisai/orca/issues/29) — Smart model routing (deferred until E0 ships)
- [#30](https://github.com/fmfsaisai/orca/issues/30) — Merge conflict resolution helper
- [#21](https://github.com/fmfsaisai/orca/issues/21) — PreToolUse hook for tmux-bridge (re-evaluate after D10)
- [#22](https://github.com/fmfsaisai/orca/issues/22) — PreToolUse bypass for read-only commands with `$VAR`
- [#23](https://github.com/fmfsaisai/orca/issues/23) — `bind-key P` capture-pane + terminal recommendations
- [#24](https://github.com/fmfsaisai/orca/issues/24) — Document Zed link-click

## Not Doing

- Rust daemon — scripts + skills enough
- Custom protocol — use tmux-bridge
- Direct model API — use CLI tools (claude / codex / gemini)
- Plugin system — skill files are plugins
- Heavy per-layer process rules
- Specialist-agent library OMC-style — Orca's diff is heterogeneous orchestration, not a curated agent catalog
- Web UI for context (E2) — TUI is the upper bound, only if usage justifies it
- Python runtime dependency — shell + sqlite3 only
- Strong structured workflows OMX-style — Orca is a "weak process" orchestrator
- Predefined `review` / `explore` / `refactor` workflow skills — earlier P1 idea; superseded by E0's `/orca dispatch` (any task uses the core skill, no per-shape skill needed). File on demand if a real use case shows up.
- `.orca/tasks/` task-dependency JSON files — D6 settled to "lead handles dependencies in head."
