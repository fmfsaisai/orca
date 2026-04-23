# Competitor Research

What we read, what we're borrowing, what we're not. Dates: 2026-04-20 / 2026-04-22 (static reads). Decisions derived from this research live in [`PLAN.md`](../../PLAN.md) (Phase E0/E1/E2 + decision rows D11+).

## Compared

| Project | Repo | Lens |
|---|---|---|
| OMC — oh-my-claudecode | [Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) | in-Agent multi-agent orchestration plugin for Claude Code |
| OMX — oh-my-codex | [staticpayload/oh-my-codex](https://github.com/staticpayload/oh-my-codex) | orchestration layer on top of Codex CLI |
| ctx | [dchu917/ctx](https://github.com/dchu917/ctx) | local context persistence for Claude/Codex sessions |
| stablyai/orca | [stablyai/orca](https://github.com/stablyai/orca) | Electron desktop multi-terminal control plane |

All MIT.

## Cross-cutting comparison

| Axis | Orca (today) | OMC | OMX | ctx | stably/orca |
|---|---|---|---|---|---|
| Entry surface | shell CLI | in-Agent (`/autopilot`, `/team`) + CLI (`omc team`) | in-Agent (`$ultrawork`) + CLI (`omx team`) | in-Agent skill (`/ctx`) | desktop GUI |
| tmux required to start | yes | no for `/team`; yes for `omc team` | no for `$ultrawork`; yes for team workers | no | no |
| Default layout | lead + N worker panes | single cc session | single codex session | single Agent session | tabs/splits inside Electron |
| Worker spawn | upfront, fixed N | on-demand (`/team N:role`) | on-demand (`omx team spawn/queue`) | n/a | per-tab on-demand |
| IPC | tmux-bridge (push) | cc Team API (in-process) / Node runtime + tmux pane | repo-local JSON queue + lease | n/a | structured RPC over local socket; PTY stream for content |
| Persistence | none (pane scrollback only) | partial (cc native + state files) | repo-local `.omx/` JSON files | **SQLite** with workstream/session/entry + FTS5 | session schema (Electron persist) |
| Liveness detection | PostToolUse heartbeat file | runtime snapshot + worker auto-restart | `leaseExpiresAt` + `reconcileWorker` | n/a | OSC title parse + AgentDetector |
| Failure recovery | none beyond pane restart | sidecar JSON + exponential backoff | stale lease visible; **no auto-requeue** | n/a | session persist |
| Heterogeneous models | first-class (cc lead + codex worker) | possible via `omc team N:codex|gemini` | Codex-only (Claude bridge removed in v2) | n/a | per-tab, model-agnostic |

## OMC — oh-my-claudecode

Multi-agent orchestration plugin for Claude Code. Tagline: "Don't learn Claude Code. Just use OMC." Currently 19 unified agents (older docs say 32 — that's a stale internal count).

### Two runtimes (this matters)

| Surface | Runtime | tmux? | Worker spawn |
|---|---|---|---|
| `/team` (in-Agent) | cc native Team API (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`); staged `team-plan → team-prd → team-exec → team-verify → team-fix` | no | in-process subagents |
| `omc team N:codex` (CLI) | detached Node runtime as control plane; tmux pane workers via `spawnWorkerInPane()` | yes | real `claude`/`codex`/`gemini` CLI inside tmux pane |

The CLI runtime is essentially the same shape as Orca's tmux model. The in-Agent runtime is the unique pattern Orca doesn't yet have.

### Verified facts

- 19 unified agents in `getAgentDefinitions()` (`src/agents/definitions.ts:212-250`).
- Codex worker is full `codex` CLI inside tmux pane with `--dangerously-bypass-approvals-and-sandbox`, NOT one-shot `--no-interactive` (`src/team/model-contract.ts:181-210`, `src/team/tmux-session.ts:269-311`).
- Hooks at install: `UserPromptSubmit / SessionStart / PreToolUse / PermissionRequest / PostToolUse / PostToolUseFailure / SubagentStart / SubagentStop / PreCompact / Stop / SessionEnd` (`docs/REFERENCE.md:620-636`).
- "Persistent mode" (no early stop) is enforced by a `Stop` hook, not by `autopilot`/`ralph`/`ultrawork` skills (`docs/HOOKS.md:230-237`).
- Setup writes to `~/.claude/{agents,skills,hooks,hud,settings.json,CLAUDE.md,.omc-version.json,.omc-config.json}`.
- Worker auto-restart: sidecar JSON + exponential backoff + `maxRestarts=3` (`src/team/worker-restart.ts:1-120`); CLI workers in particular rely on tmux kill + runtime detection rather than `shutdown-ack.json`.
- Issue #716 (default tmux-wrap + `--no-tmux`): closed; website docs adopt the direction; main launcher source not fully traced.
- "30-50% token saving" is author claim attributed to `Smart model routing`; no public benchmark methodology found.

### Take for Orca

| Pattern | Take | How |
|---|---|---|
| In-Agent entry (`/autopilot`) | adopt | `/orca dispatch` skill (Phase E0) |
| Hooks always-registered, behavior gated by skill activation | adopt | install registers full hook set; bodies are no-op until `/orca` skill activates |
| `omc team` CLI runtime | already have | Orca's existing `orca` CLI is the same shape |
| 19 unified agents catalog | skip | Orca's diff is heterogeneous orchestration, not curated specialists |

## OMX — oh-my-codex

Orchestration layer for OpenAI Codex CLI. "Like oh-my-zsh but for Codex." Persistent state + memory + structured workflows (`$ultrawork` / `$tdd` / `$plan` / `$deep-interview`). Three-step onboarding: `omx setup` → `omx doctor` → `omx hud`. README still mentions "Async Claude Code delegation" but v2 source + FAQ confirm the Claude bridge is gone (stale marketing copy).

### Verified facts

- Top-level CLI: `setup`, `doctor`, `hud`, `team`, `explore`, `session`, `autoresearch`, `agents`, `plugins`, `hooks`, `version`. `team` subcommands: `init|status|spawn|queue|claim|heartbeat|complete|review|message|await|inbox|logs|resume|shutdown` (`packages/cli/src/help.ts`, `commands/team.ts`).
- **Queue model**: `team.json` carries `taskQueue: string[]`. `queueTeamTask()` enqueues; `claimTeamTask()` flips worker→busy, writes `leaseExpiresAt`, removes from queue, marks task `in_progress` (`packages/core/src/team.ts:37-289`). Repo-local JSON queue + lease, **no socket, no flock**.
- **Persistent state**: repo-local `.omx/{state,sessions,plans,research,team,logs,memory,hud-config.json}` — JSON files, not SQLite (`docs/ARCHITECTURE.md:53-78`).
- **Memory**: `memory/<namespace>.json` → `{namespace, summary, facts[], updatedAt}` — project summary + facts, not transcript replay (`packages/core/src/memory.ts:21-48`).
- **HUD**: plain-text dashboard, fields `Branch / Session / Tasks / Modes / Team / Inbox / Priority note / Memory / Autoresearch` (`packages/core/src/hud.ts:68-93`). Not curses/TUI.
- **Hooks**: `SessionStart / PreToolUse / PostToolUse / UserPromptSubmit / Stop` (`packages/core/src/hooks.ts:7-21`). Presets: `workspace-context / memory / safety / review / telemetry`. Codex hooks still experimental; Pre/PostToolUse mostly Bash; no Windows.
- **Failure recovery**: `leaseExpiresAt` lets `reconcileWorker()` mark `busy` workers as `stale`. Tasks are removed from `taskQueue` on claim and **do NOT auto-requeue** on worker death — operator must intervene.
- **git worktree**: not verified that `team` runtime auto-creates per-worker worktrees; current implementation centers on tmux session/window + `.omx/` durable state.

### OMC vs OMX in one line

| Axis | OMC | OMX |
|---|---|---|
| Host | Claude Code | Codex CLI |
| Entry | `/autopilot` (auto-route via 19 agents) | `$ultrawork` (queue + explicit claim) |
| Philosophy | "auto first" — minimize user choice | "explicit control" — preserve operator hand |

### Take for Orca

| Pattern | Take | Phase |
|---|---|---|
| In-Agent skill entry (`$ultrawork`) | adopt — same shape as OMC `/autopilot` | E0 |
| `omx doctor` self-check | adopt | E0.e |
| **Queue + worker claim** | adopt — replaces lead's hard `tmux-bridge message` push with worker self-pick | E1 |
| `omx hud` text dashboard | adopt — Orca lacks global observability | E1 (`orca hud`) |
| Repo-local JSON state files | partial — for ctx (E2) we go SQLite; JSON OK for small ephemeral state |  |
| TDD/plan/review skills | skip-by-default — Orca is "weak process"; could ship as optional skills |  |

## ctx — local context persistence

Local-first context store for Claude Code / Codex sessions. SQLite at `~/.contextfun/context.db` (or repo-local). Python 3.9+ standard library only — no third-party deps, no API key, no hosted service. Web UI is loopback-only with random token. Code in `contextfun/cli.py`, `contextfun/web.py`, `scripts/ctx_cmd.py`.

Borrow the **data model**, not the runtime. Direct dependency would pull Orca from "shell-only orchestrator" toward "local Python app."

### Data model (the part worth borrowing)

```
workstream  (slug, title, description, tags, workspace, metadata)
   └─ session  (workstream_id, agent, workspace, metadata)
        ├─ entry  (session_id, type, content, extras)
        │     └─ extras.load_behavior ∈ {default, pin, exclude}
        └─ session_source_link  (source, external_session_id,
                                  transcript_path, transcript_mtime,
                                  message_count)
ctx_meta  (search_index_version, …)
search_index  (FTS5 virtual table over workstream/session/entry)
```

Key separations:
- **Three-layer storage** instead of flat log: workstream → session → entry.
- **External transcript binding lives in its own table** (`session_source_link`), not in `entry`. Lets you re-pull a transcript without touching saved entries.
- **`pin` / `exclude` load control on entry**: excluded entries stay searchable but never enter future load packs; pinned entries are forced in. Critical for noise control.

### Mechanisms

- **Transcript discovery**: scans `~/.codex/sessions`, `~/.claude/projects` (overridable). "Current session" via env vars (`CODEX_THREAD_ID` / `CLAUDE_*`), then by reverse-lookup. Workspace filtering extracts `cwd` from transcript header — "newest matching this repo," not "newest file."
- **Incremental pull**: `session_source_link.message_count` + re-read transcript → ingest delta only (`scripts/ctx_cmd.py:2124-2195`). This is what "no transcript drift" means in code.
- **Snapshot branch** (most relevant for Orca): `branch <src> <dst>` snapshot-copies sessions/entries/attachments, marks `branch_snapshot_from`, **does not copy `session_source_link`**. Future `pull` on either side stays independent (`scripts/ctx_cmd.py:765-900`).
- **Search**: SQLite FTS5 virtual table over text; per-row rebuild on change; LIKE fallback in web layer.
- **Integration**: invoked via Claude/Codex *skills*, not hooks. Skills call `ctx` CLI, which reads SQLite + transcript files.

### Take for Orca (Phase E2)

Direct lifts (port the design, write our own implementation):

| Borrow | Orca shape |
|---|---|
| `workstream → session → entry` three-layer | same names; `entry.type` extended for `dispatch / report / decision / todo / note / tool_output / transcript_delta` |
| `session_source_link` binding table | `source ∈ {tmux, claude, codex, manual}`; `transcript_path` becomes optional (tmux pane has no file) |
| `message_count` incremental pull | port verbatim — solves "worker session died, lost context" |
| Snapshot branch (does NOT copy source link) | port verbatim — Orca's multi-worktree case needs this *more* than ctx does |
| `pin` / `exclude` load control | port verbatim — Orca has worse signal-to-noise (tool output spam) |
| Workspace-aware transcript selection | extend — match on (repo, worktree, pane, worker label), not just repo |

Adaptations:

| Issue | Adaptation |
|---|---|
| `current.<slot>.json` single-file pointer | won't survive multi-pane — use `current.<session>.<pane>.json` or an `agent_slot` table |
| Transcript discovery hard-coded to Claude/Codex paths | need a **source adapter** layer: discover / extract-id / pull-delta as plugin contract; first adapters = `tmux`, `claude`, `codex` |
| Web UI | skip in E2; TUI as upper bound |

Don't take: direct ctx runtime dependency, Python core, hard-coded transcript-source paths in core.

## stablyai/orca — Electron multi-terminal control plane

Different shape entirely: an Electron desktop app whose main process owns terminal handles and exposes a structured RPC. Reviewed at tag 1.3.6 (commit `c47b651`, 2026-04-19). Only takeaways relevant to Orca's shell+tmux+skill product are summarized; the Electron control plane is out of scope.

### Mechanisms worth noting

- **Stable addressable handles** — `OrcaRuntimeService` (`src/main/runtime/orca-runtime.ts:138-198`) maintains tabs/leaves/handles/waiters; the runtime exposes `terminal.list/show/read/send/wait` + `worktree.ps/list/create` as RPC methods (`src/main/runtime/runtime-rpc.ts:218-385,524-573`). Each terminal pane is an addressable object, not a label-on-a-tmux-server.
- **Local RPC over socket + auth token** — `runtime-rpc.ts:50-156` runs a local socket server with random `authToken`; bootstrap metadata (`orca-runtime.json`) carries `transport` + `authToken` for CLI consumers (`src/shared/runtime-bootstrap.ts:13-24`).
- **PTY stream + structured RPC instead of shell args** — content reaches renderer via `pty:data` (`src/main/ipc/pty.ts:196-240`); long messages don't need to fit in shell argv. Sidesteps quoting / `$(...)` / multi-line problems entirely.
- **Library-grade worktree** — `src/main/git/worktree.ts:30-191`, `src/main/ipc/worktree-logic.ts:8-121`. Path-traversal guards, Windows/WSL normalization, prune + branch cleanup on remove. Orca's `orca-worktree.sh` is the slim version of this.
- **PTY-based agent state detection** — `AgentDetector` (`src/main/stats/agent-detector.ts:60-140`) reads OSC titles, distinguishes `working / permission / idle`, debounces ANSI noise. `agent-detection.ts` recognizes `claude`, `codex`, `gemini`, `opencode`, `aider`. This is observation of the *terminal/agent runtime*, complementary to Orca's tool-call heartbeat which observes *tool activity*.

### Take for Orca (long-tail, not E0/E1/E2)

| Pattern | Take |
|---|---|
| Stable handles + structured ops vs label/socket addressing | borrow the *interface shape* if we need a registry layer; could let `/orca dispatch` discovery (M3 path) and the future ctx adapter share one `{session, worker_id, pane_label, pid}` registry. Out of scope for E0. |
| Reduce structured content stuffed into shell args | already addressed at the message layer by D10 (file handoff). |
| Terminal-state detection (OSC title) as a complementary signal | possible additional source adapter for E2 (`source = tmux-title`). |
| Library-grade worktree | Orca's needs are simpler today; revisit if multi-platform / SSH / WSL show up. |
| Electron control plane | not applicable — wrong product shape. |

## What we are explicitly NOT borrowing

| From | Pattern | Why not |
|---|---|---|
| OMC | 19-agent specialist catalog | Orca's diff is heterogeneous orchestration, not a curated catalog |
| OMX | Strong structured workflow (TDD/plan/review as core) | Orca is a "weak process" orchestrator |
| OMX | "Async Claude delegation" marketing on retired feature | anti-pattern — keep marketing aligned with code |
| ctx | Web UI | TUI is upper bound; only if usage demands |
| ctx | Python runtime in core | preserve shell-only philosophy; use `sqlite3` CLI |
| stablyai/orca | Electron control plane | wrong product shape for shell+skills |

## Sources

- OMC: [README](https://github.com/Yeachan-Heo/oh-my-claudecode) · [REFERENCE](https://github.com/Yeachan-Heo/oh-my-claudecode/blob/main/docs/REFERENCE.md) · [Issue #716](https://github.com/Yeachan-Heo/oh-my-claudecode/issues/716)
- OMX: [GitHub](https://github.com/staticpayload/oh-my-codex) · [Verdent — what is OMX](https://www.verdent.ai/guides/what-is-oh-my-codex-omx)
- ctx: [GitHub](https://github.com/dchu917/ctx) · [`contextfun/cli.py`](https://github.com/dchu917/ctx/blob/main/contextfun/cli.py) · [`scripts/ctx_cmd.py`](https://github.com/dchu917/ctx/blob/main/scripts/ctx_cmd.py)
- stablyai/orca: [GitHub](https://github.com/stablyai/orca) · reviewed at tag 1.3.6 / commit c47b651
