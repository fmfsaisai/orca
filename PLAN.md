# Orca Plan

## Vision

Model-agnostic multi-agent orchestrator. Any model combination as lead/worker. tmux-bridge + skills.

Differentiator: **mixed models + configurable roles + preset workflows**.

Inspired by [oh-my-claudecode](https://github.com/anthropics/oh-my-claudecode) (multi-agent workflow, heartbeat/idle detection) and [oh-my-codex](https://github.com/openai/codex) (Codex hooks automation). Orca adds model-agnostic orchestration on top.

## Completed

- [x] tmux session + split panes + lead/worker launch
- [x] tmux-bridge communication (push, not poll)
- [x] Shared skill with role by activation command (`/orca`=lead, `$orca`=worker)
- [x] `$ORCA_PEER` dynamic peer targeting (multi-instance safe)
- [x] SessionStart hooks (CC auto `/orca`, Codex prompt parameter)
- [x] Codex /clear monitor (semi-auto, user presses Enter)
- [x] Global command `orca` with subcommands (`orca`, `orca stop`, `orca idle`, `orca ps`, `orca rm`, `orca prune`) — see PR #5
- [x] install.sh (smux + commands + skills + hooks)
- [ ] Full pipeline e2e: dispatch → code → /review → report → /simplify → user report

Known issues:
- Codex /clear needs 2x Enter (tmux can't send to ratatui TUI)
- Codex sandbox workaround (openai/codex#10390)

## Decisions

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| D1 | Worker completion notification | Heartbeat + state transition + cooldown | PostToolUse every call too noisy; pure skill text unreliable; borrowed from OMC |
| D2 | Multi-worker merge order | Lead decides per workflow | refactor=dependency order, code=first-done-first-merge |
| D3 | Mixed worker hooks | Each uses native hooks, Skill + tmux-bridge is the unified layer | CC hooks ≠ Codex hooks.json, but hook scripts shared |
| D4 | Workflow skill style | Hybrid: fixed checkpoints + principles between (light process) | Inspired by OMC's layered approach |
| D5 | Worktree timing | On-demand at dispatch time | User may need only 1 worker |
| D6 | Task dependencies | B first (task files + blocked_by) → simplify to A (pure lead judgment) | Start with guardrails, remove if lead is smart enough |
| D7 | Multi-instance per dir | TBD — direction: Claude Code resume-style picker (list existing + "new") | Current `orca-<dirname>` collides on re-run; explicit `--name` flag rejected as too manual |
| D8 | tmux server scope | Per-instance dedicated server via `tmux -L orca-<dirname>` | User's main tmux server caches stale env globally; sharing it pollutes user state. Per-instance server: stop=kill server=clean env, start=fresh fork from current shell. Overhead ~5MB/instance, negligible. See [docs/troubleshooting/tmux-server-stale-env.md](docs/troubleshooting/tmux-server-stale-env.md) |
| D9 | Lead/worker model selection | `--lead MODEL --worker MODEL` flags + `$ORCA_ROLE` env var | Resolved: role-by-env-var (`$ORCA_ROLE`) decouples role from activation command. Any binary can be lead or worker. `model_cmd()` maps model names to launch commands. See [docs/design/multi-worker.md](docs/design/multi-worker.md). |
| D10 | Structured content delivery channel | Inline single-quoted `tmux-bridge message` is the default; switch to file on disk (`/tmp/orca-msg-*.md`) only when content contains `'` or newlines | Tested `tmux load-buffer + paste-buffer` (Tier 1) — content reaches worker intact, but Codex multi-line paste needs Enter×2 (timing-sensitive) and full body lands in worker conversation history (compaction risk). Single-quote wrapping makes most short messages safe inline, so the file fallback only triggers on `'` or newlines — narrow scope, low overhead. File delivery (when triggered) keeps worker context lean (path-only message), is auditable, and uses one mental model for all structured content. Smux/`tmux-bridge` source is upstream so no code-level guard is added; rule is enforced by SKILL discipline. |

## Target Architecture

```
orca --lead claude --worker codex --workers 3 --worktree --workflow code

┌─ lead (claude) ──────┬─ w1 (codex) ─┬─ w2 (codex) ─┬─ w3 (codex) ─┐
│ dispatch + optimize  │ worktree/w1  │ worktree/w2  │ worktree/w3  │
│ Skill: lead          │ Skill: worker│ Skill: worker│ Skill: worker│
│ tmux-bridge          │ hooks + tmux │ hooks + tmux │ hooks + tmux │
└──────────────────────┴──────────────┴──────────────┴──────────────┘
```

Worktrees are used when `--worktree` is enabled; multi-worker mode requires it. Single-worker mode works directly in `$ORCA_ROOT` by default.

## P0: Multi-Worker + Isolation + Hooks

**start.sh**
- [x] `--workers N` — max workers (default 1), multi-pane creation
- [x] `--lead <model>` / `--worker <model>` — model selection (resolves D9: role from `$ORCA_ROLE` env var)
- [x] `--workflow <name>` — load workflow skill

**Worktree**
- [x] On-demand `<repo>/.orca/worktree/<slug>` at dispatch (D5)
- [x] `orca-worktree create/remove/list/clean` helper (`<slug>` = kebab-case feature name; append `-<n>` only for same-feature multi-worker splits)
- [x] stop.sh cleanup
- [x] Smoke test：worker 在 worktree 内读取主仓 `.gitignored` 资源（`.claude/settings.local.json`），验证 `$ORCA_ROOT` 访问可用

**Hooks** (D1, D3)
- [x] `hooks/post-tool-use.sh` — worker heartbeat (PostToolUse)
- [x] `hooks/check-heartbeat.sh` — lead idle check (PreToolUse)
- [x] install.sh registers PostToolUse/PreToolUse hooks for CC
- [x] `.orca/heartbeat/` — 30s per-worker cooldown

**Multi-instance per dir** (D7, design TBD)
- [ ] Re-running `orca` in a dir with existing session(s): prompt to attach existing or start new (Claude Code resume-style)
- [ ] Naming/identification scheme for multiple instances under same dir
  - **Constraint**: scheme must keep the `<type, name, cwd>` tuple unique per instance, since `_lib.sh:short_id` hashes that tuple to produce the `orca ps` / `orca rm` id. Cleanest fit: bake the disambiguator into `name` (e.g. `orca-<dirname>-2`), then no id-formula change needed.
- [x] `orca stop` / `orca ps` / `orca rm` already adapt to multi-instance (rm uses id to disambiguate; ps lists every instance independently) — landed in PR #5
- [ ] `orca` start path: prompt to pick existing-or-new when target name already exists

**tmux server isolation** (D8) — landed in PR #4
- [x] `start.sh` / `stop.sh` use `tmux -L orca-<dirname>` for a dedicated per-instance server
- [x] `stop.sh` does `tmux -L ... kill-server` (server only owns this one session, kill = clean env)
- [x] Verify `tmux-bridge` auto-detects via `$TMUX` (zero changes needed; out-of-pane `name` calls pass `TMUX_BRIDGE_SOCKET`)
- [x] Pre-D8 legacy session cleanup in `stop.sh` (orphan sessions on user's main tmux are detected + removed alongside dedicated)
- [x] Sanitize `.` and `:` in dir basename (pre-existing bug surfaced during D8 smoke test)

## P1: Workflow Skills

Light core skill + moderate workflow skills (D4).

```
skills/orca/SKILL.md              # core (current)
skills/workflows/code/SKILL.md    # dispatch → parallel code → merge → optimize  ✅
skills/workflows/review/SKILL.md  # dispatch → parallel review → aggregate
skills/workflows/explore/SKILL.md # dispatch → parallel research → synthesize
skills/workflows/refactor/SKILL.md # dispatch → parallel refactor → sequential merge
```

## P2: Task Dependencies (D6: B→A)

- [ ] `.orca/tasks/` task JSON (id, status, blocked_by)
- [ ] `orca-task create/update/list/ready` — removable if lead handles it alone

## P3: Worker Lifecycle

- [ ] Heartbeat (reuse P0), timeout, retry, communication logs

## P4: Advanced

- [ ] PreToolUse safety (block rm -rf, force push)
- [ ] Model routing (complex→Claude, bulk→GPT)
- [ ] Merge conflict resolution

## Not Doing

- Rust daemon — scripts + skills enough
- Custom protocol — use tmux-bridge
- Direct model API — use CLI tools (claude / codex / gemini)
- Plugin system — skill files are plugins
- Heavy per-layer process rules
