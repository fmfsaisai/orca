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

## Target Architecture

```
orca --lead claude --worker codex --workers 3 --workflow code

┌─ lead (claude) ──────┬─ w1 (codex) ─┬─ w2 (codex) ─┬─ w3 (codex) ─┐
│ dispatch + optimize  │ worktree/w1  │ worktree/w2  │ worktree/w3  │
│ Skill: lead          │ Skill: worker│ Skill: worker│ Skill: worker│
│ tmux-bridge          │ hooks + tmux │ hooks + tmux │ hooks + tmux │
└──────────────────────┴──────────────┴──────────────┴──────────────┘
```

## P0: Multi-Worker + Isolation + Hooks

**start.sh**
- [ ] `--workers N` — max workers (default 1), lead creates panes on demand
- [ ] `--lead <model>` / `--worker <model>` — model selection
- [ ] `--workflow <name>` — load workflow skill

**Worktree**
- [ ] On-demand `<repo>/.orca/worktree/<id>` at dispatch (D5)
- [ ] `orca-worktree create/remove` helper
- [ ] stop.sh cleanup

**Hooks** (D1, D3)
- [ ] `hooks/post-tool-use.sh` — heartbeat + idle detection + tmux-bridge notify
- [ ] Auto-generate `.codex/hooks.json` (Codex) / CC hooks per worker
- [ ] `.orca/heartbeat/` — cooldown: 30s per-worker, 60s all-idle

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
skills/workflows/code/SKILL.md    # dispatch → parallel code → merge → optimize
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
