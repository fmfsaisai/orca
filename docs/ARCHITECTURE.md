# Architecture

Current implementation overview. For the next-step direction (entry refactor + comm continuity + ctx), see [`PLAN.md`](../PLAN.md). Per-call dispatch mechanics live in [`design/dispatch-runtime.md`](design/dispatch-runtime.md).

## Layered model

```
Lead ←→ Worker

┌─────────────────────────────────────────────┐
│  Skill layer (skills/orca/SKILL.md)         │  what to say
│  "dispatch task, report result"             │
├─────────────────────────────────────────────┤
│  tmux-bridge layer (smux)                   │  how to say it
│  read → message → read → keys Enter         │
├─────────────────────────────────────────────┤
│  tmux layer                                 │  transport
│  send-keys / capture-pane / pane buffers    │
└─────────────────────────────────────────────┘
```

## Key decisions

- **tmux over pipes** — persistent sessions, mature IPC, human can switch panes.
- **smux over raw tmux** — `tmux-bridge read coder 100` saves tokens vs raw capture-pane; Read Guard prevents blind ops.
- **Push over poll** — workers push via `tmux-bridge message`; the early `wait-for-idle.sh` polling had false positives and wasted tokens.
- **2 agents over 3** — Reviewer removed; Codex `/review` + Claude `/simplify` covers it. Cross-model review > same-model independent reviewer.
- **Shared skill** — one `skills/orca/SKILL.md` for both roles. Role from `$ORCA_ROLE` env var (not activation command). See [Multi-worker](#multi-worker) for why.
- **Heartbeat via hooks, not background monitor** (D1) — see [Heartbeat](#heartbeat).
- **On-demand worktrees** (D5) — `orca-worktree create` at dispatch time; `<slug>` is kebab-case feature name with optional `-<n>` for same-feature splits.
- **Handoff files** (D10) — long-context dispatch and reports use `/tmp/orca-{handoff,msg}-<slug>-<ts>.md`; inline single-quoted message is the default; switch to file when content has `'` or newlines. See [Communication](#communication).
- **Codex sandbox** — macOS Seatbelt `network_access=true` is broken for AF_UNIX (openai/codex#10390); we run with `--sandbox danger-full-access -a on-request` until upstream fixes it.
- **Codex activation** — startup uses prompt parameter (auto). After `/clear`, monitor + user Enter (tmux can't send Enter to Codex's ratatui TUI under the Kitty keyboard protocol).
- **Per-instance tmux server** (D8) — `tmux -L orca-<dirname>` isolates orca from the user's main tmux server; stop = kill server = clean env.

## Communication

### Protocol

All lead↔worker exchanges are a single `&&`-chain:

```bash
tmux-bridge read $ORCA_PEER 5 && \
tmux-bridge message $ORCA_PEER "msg" && \
tmux-bridge read $ORCA_PEER 5 && \
tmux-bridge keys $ORCA_PEER Enter
```

1. `read` — wait for peer's pane (Read Guard; without it, keystrokes can arrive mid-output and garble).
2. `message` — type into peer's input.
3. `read` — wait for text to appear.
4. `keys Enter` — submit.

### Message body — inline vs handoff (D10)

| Body shape | Channel |
|---|---|
| short single-line, no `'` or newline | inline single-quoted: `tmux-bridge message $PEER 'body'` |
| multi-line, contains `'`, or contains markdown code spans | file handoff: write `/tmp/orca-{handoff,msg}-<slug>-<ts>.md`, send `Read $path` |

`orca-handoff-*` = dispatch direction (lead → worker); `orca-msg-*` = report direction (worker → lead). Both are auto-cleaned on reboot (`/tmp` semantics) and survive worker restart.

### Multi-worker addressing

`$ORCA_WORKERS` is the CSV of all worker labels; `$ORCA_PEER` always points to a fixed counterpart (worker-1 from lead's view, lead from any worker's view). Address a specific worker by label literal:

```bash
# $ORCA_WORKERS = "orca-myproj-worker-1,orca-myproj-worker-2,orca-myproj-worker-3"
tmux-bridge message orca-myproj-worker-2 "Your task: ..."
```

## Multi-worker

```
orca --lead claude --worker codex --workers 3 --workflow code

┌─ lead (claude) ──────┬─ w1 (codex) ─┬─ w2 (codex) ─┬─ w3 (codex) ─┐
│ ORCA_ROLE=lead       │ ORCA_ROLE=   │ ORCA_ROLE=   │ ORCA_ROLE=   │
│ ORCA_WORKERS=w1,w2,w3│   worker     │   worker     │   worker     │
│ Skill: orca          │ ORCA_PEER=   │ ORCA_PEER=   │ ORCA_PEER=   │
│                      │   lead       │   lead       │   lead       │
└──────────────────────┴──────────────┴──────────────┴──────────────┘
```

### Why `$ORCA_ROLE` instead of activation command

Earlier design coupled role to runtime: `/orca` for cc lead, `$orca` for codex worker. A cc *worker* would need to run `/orca` but behave as worker — contradiction. Now both agents run the same activation for their platform; the skill reads `$ORCA_ROLE` to branch. Any model can be any role.

### Model command mapping

`start.sh` maps model names to launch commands:

```
claude  → claude
codex   → codex --sandbox danger-full-access -a on-request ...
gemini  → gemini  (future)
<other> → passed through as-is
```

`orca --worker ./my-agent` accepts custom binaries.

### Environment variables

| Variable | Lead | Worker |
|---|---|---|
| `ORCA` | `1` | `1` |
| `ORCA_ROLE` | `lead` | `worker` |
| `ORCA_PEER` | first worker label | lead label |
| `ORCA_WORKERS` | all worker labels (csv) | — |
| `ORCA_WORKER_ID` | — | `1`, `2`, … |
| `ORCA_ROOT` | repo root (absolute) | repo root (absolute) |
| `ORCA_WORKFLOW` | workflow name | workflow name |

`ORCA_ROOT` is always the main repo root, even when a worker `cd`s into a worktree. The heartbeat hooks rely on this to write to the shared `.orca/heartbeat/`.

### Worktree isolation

```
project/
  .orca/
    worktree/
      task-1/    # worker 1's isolated copy
      task-2/    # worker 2's isolated copy
    heartbeat/
      1          # worker 1's heartbeat
      2          # worker 2's heartbeat
```

Lifecycle: `orca-worktree create <slug>` → lead tells worker `cd .orca/worktree/<slug>` → worker commits to branch `orca-<slug>` → lead merges into the main branch → `orca-worktree remove <slug>` (or `orca stop` cleans all).

Merge strategy is per-workflow (D2): `code` workflow uses first-done-first-merge to minimize conflict surface; `refactor` uses dependency order.

### Pane layout

```
even-horizontal:

┌─────────┬─────────┬─────────┬─────────┐
│  lead   │  w1     │  w2     │  w3     │
│  pane 0 │  pane 1 │  pane 2 │  pane 3 │
└─────────┴─────────┴─────────┴─────────┘
```

Pane labels via `tmux-bridge name`: `{session}-lead`, `{session}-worker-{i}`. `SOCKET_PATH` passed to `tmux-bridge` for out-of-pane naming calls.

### Codex `/clear` monitor

Each Codex worker pane has a background `_skill_monitor` that watches for the Codex welcome banner (after `/clear`) and re-types `$orca` / `/orca` to re-activate the skill. Per-pane PID files at `/tmp/orca-monitor-{session}-worker-{i}.pid`. Cleaned up by `orca stop`.

## Heartbeat

### Mechanism

```
Worker side (PostToolUse):
  every tool call → write epoch seconds to .orca/heartbeat/<worker-id>

Lead side (PreToolUse):
  every tool call → read .orca/heartbeat/*, check age
  if any > 30s → emit "[orca] Idle: worker-1(45s)" into lead's context
```

Worker hook (`hooks/post-tool-use.sh`):

```bash
[[ "${ORCA_ROLE:-}" != "worker" ]] && exit 0
date +%s > "${ORCA_ROOT:-.}/.orca/heartbeat/${ORCA_WORKER_ID:-0}"
```

Lead hook (`hooks/check-heartbeat.sh`) reads timestamps and emits `[orca]` lines into the lead's context, where the LLM sees them and can act.

### Limitations

- **Not real-time**: notifications surface only when lead uses a tool. Real-time push is the worker's `tmux-bridge message` "I'm done"; heartbeat is supplementary.
- **Idle ≠ done**: a 30s-quiet worker could be done, stuck, modal-prompted, or just thinking. Lead must `tmux-bridge read <worker>` to inspect.

### Why not a background monitor

A daemon watching heartbeats and pushing tmux-bridge notifications would give real-time idle detection. Deferred: (1) race condition if lead is mid-output when monitor sends; (2) one more PID-managed background process; (3) push-based worker reports already cover the happy path. Planned to revisit alongside Worker Lifecycle work.

## Install side effects

| Path | Action |
|---|---|
| `~/.local/bin/{orca,orca-worktree}` | symlinks |
| `~/.claude/skills/{orca,orca-code}` | symlinks |
| `~/.agents/skills/{orca,orca-code}` | symlinks |
| `~/.claude/settings.json` | SessionStart + PostToolUse + PreToolUse hooks |
| `~/.smux/bin/` | install smux binary |

`start.sh` also sets per-session: `mode-keys vi`, `mouse on`, `bind-key Space even-horizontal`.

## References

- [smux](https://github.com/ShawnPana/smux) — tmux-bridge upstream
- [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — API-mode alternative
- [adversarial-review](https://github.com/alecnielsen/adversarial-review) — cross-model review pattern
- [Addy Osmani — code agent orchestra](https://addyosmani.com/blog/code-agent-orchestra/) — multi-agent analysis
- [Kaushik Gopal — agent forking](https://kau.sh/blog/agent-forking/) — "A Bash script and tmux. That's it."
