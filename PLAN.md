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
- [x] `--workers N` — max workers (default 1), multi-pane creation
- [x] `--lead <model>` / `--worker <model>` — model selection (resolves D9: role from `$ORCA_ROLE` env var)
- [x] `--workflow <name>` — load workflow skill

**Worktree**
- [x] On-demand `<repo>/.orca/worktree/<id>` at dispatch (D5)
- [x] `orca-worktree create/remove/list/clean` helper
- [x] stop.sh cleanup

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

## 通信层重构（Tier 1：paste-buffer）

**起源**：`docs/research/stably-orca-compare.md` 指出，`docs/proposals/mixed.md` 中 #1 和 #2（以及部分 #3）的根因是「将结构化指令塞入 shell 命令参数」。

**目标**：让 `tmux-bridge` 的内容传递路径绕开 bash 解析。

**方案**：将 `send-keys -l` 的内容通道替换为 `tmux load-buffer + paste-buffer`。
- 新增 `tmux-bridge message-file <target> <path>` 子命令
- 内部实现：`tmx load-buffer -b <name> <path> && tmx paste-buffer -t <target> -b <name>`
- 原 `send-keys` 仍用于控制按键（Enter、Esc 等）

**范围**
- [ ] `tmux-bridge` `message-file` 子命令
- [ ] Smoke test：Claude Code / Codex 在 bracketed paste 下的行为验证
- [ ] `skills/orca/SKILL.md` 通信规则更新：结构化内容一律走 `message-file`
- [ ] `docs/proposals/mixed.md` #1 收尾：方案 A/B 仍作为 fallback，但不再是主线

**不在本范围内**（推迟到 Tier 2/3，详见研究文档）
- Agent 原生 hook 注入（按 agent 单独适配，脆弱）
- Sidecar RPC 进程（接近 stably Electron 模式，过重）

**待澄清**
- 不同 agent 对 bracketed paste 的兼容性
- buffer 名称管理与清理策略

## 待落地的 Skill 规则（留到独立的实施 PR）

以下规则会直接修改 `skills/orca/SKILL.md`，merge 后立刻改变 worker 行为。本 PR 是研究 + 规划范畴，特意将这些规则拆出来，放到独立 PR 单独 review 与 smoke test。

### 规则 1：Worker → Lead 汇报 fallback（过渡方案，等 Tier 1 落地后被取代）

插入位置：`## Communication` 段的 `Multi-worker:` 行之后。

```markdown
Worker → Lead reply rules:
> Current solution. Will be superseded by Tier 1 (paste-buffer) once landed; see `PLAN.md` "通信层重构（Tier 1：paste-buffer）".

- Single-line short message (no backticks, no `$`, no newlines) → keep inline, wrap body in single quotes
- Multi-line / contains backticks / contains `$` / contains markdown code block / needs cross-worker reuse → write report to `/tmp/orca-msg-<task-slug>-<timestamp>.md`, reuse the dispatch handoff slug, then send only the path

​````bash
msg_path="/tmp/orca-msg-auth-refactor-$(date +%s).md"
cat > "$msg_path" <<'EOF'
Full report body can include `code`, $VARS, 'quotes', and real newlines.
EOF
tmux-bridge read "$ORCA_PEER" 5 && tmux-bridge message "$ORCA_PEER" "Read $msg_path" && tmux-bridge read "$ORCA_PEER" 5 && tmux-bridge keys "$ORCA_PEER" Enter
​````
```

另外在 `## Lead` 第 2 步「Long-context tasks」那条之后追加：

```markdown
- Symmetric for worker → lead reports; see Communication > Worker → Lead reply rules.
```

并在 `## Worker` 第 3 步的 Report 行末尾追加 `(follow Communication rules for inline vs file)`。

**起源**：本 PR 中暴露的漏洞 —— `mixed.md` 宣称落盘是 fallback，但 `SKILL.md` 内并不存在对应的可执行规则。

### 规则 2：Worktree 文件系统访问约定

插入位置：`## Communication` 与 `## Lead` 之间，作为新的顶层段。

```markdown
## Worktree Filesystem Access

Worktrees share `.git` but have isolated working trees. **`.gitignored` artifacts do not propagate across worktrees**:
- `node_modules/` / `dist/` / build caches
- Manually cloned reference repos (e.g. `docs/research/reference-repos/<repo>/`)
- Local secrets / configs (`.env`, `.claude/`, etc.)

When an agent working inside a worktree needs these resources:

| Operation | Path |
|---|---|
| **Read** main repo's `.gitignored` resources | `$ORCA_ROOT/<path>` (main repo absolute path, env already set) |
| **Write** task code | current worktree (`pwd`) |
| **Write** cross-task shared research / reference data | `$ORCA_ROOT/<path>`, must be explicitly stated in the task |

Do not re-install / re-clone / re-build resources that already exist in the main repo — wastes time and disk, and risks divergence from main repo state.
```

**起源**：与 Tier 1 无关。来自 worker 在 worktree 内重新 clone 资源的实际事故，抽象为一条 skill 层面的通用约束。

### 实施 PR 的范围（独立）

- [ ] 将规则 1 应用到 `skills/orca/SKILL.md`
- [ ] 将规则 2 应用到 `skills/orca/SKILL.md`
- [ ] Smoke test：派一个会触发多行汇报的 worker，验证 `/tmp/orca-msg-*` 流程
- [ ] Smoke test：派一个进入 worktree 后需要读取主仓 `node_modules` 或参考 clone 的 worker，验证 `$ORCA_ROOT` 访问可用

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
