# Dispatch Runtime

Per-call mechanics for `/orca <task>`. Phase + scope tasking lives in [`PLAN.md`](../../PLAN.md) Phase E0; this doc owns the runtime model.

## Premise

`orca` CLI ships shell utilities + conventions only (`tmux-bridge`, `orca-worktree`, `orca {ps, stop, doctor, hud}`). The **host agent (cc/codex) runs the orchestration logic** via the `/orca` skill. There is no `start.sh`-style "set up a fixed lead+worker frame" step — host agent decides per call whether to spawn anything at all.

The `/orca` skill **is the workflow**. It hardcodes "implement → /review → test → report" (the existing `code` workflow). No `--workflow` flag. Future workflows ship as new slash commands (`/orca-tdd`, `/orca-review`, etc.). Same shape as OMC `/autopilot`.

## Entry

```
/orca <task> [--workers N] [--worker MODEL] [--mode auto|inline|subagent|pane] [--no-worktree]
```

Bare `/orca` (no args) → print usage. No env-var role detection, no SessionStart auto-fire — entry is always user-initiated.

| Flag | Default | Notes |
|---|---|---|
| `--workers N` | 1 | parallelism count |
| `--worker MODEL` | host agent | `claude` / `codex` / path to binary |
| `--mode` | `auto` | force a specific mode; `auto` = resolution rules below |
| `--no-worktree` | off | skip worktree creation (worker writes to main repo) |

## The three modes

| Mode | Worker is | Task delivery | Result delivery | When |
|---|---|---|---|---|
| **inline** | the current host agent (no spawn) | user's `/orca <task>` input | host completes in the same conversation | single task, no parallelism asked, worker model = host |
| **subagent** | a child agent of the host (cc Task tool) | Task tool's `prompt` parameter | Task tool's return value (sync, blocking) | parallelism asked but no tmux available, or worker model = host |
| **pane** | a real `cc` / `codex` process in a tmux pane | short task: `tmux-bridge` paste; long task: `.orca/dispatches/<ts>/<slug>.md` + paste path | `tmux-bridge` push notification + `.orca/reports/<ts>-<slug>.md` file | parallelism asked AND in tmux AND (worker model ≠ host OR user wants visibility) |

**Examples**:

| User input | Resolved mode | What happens |
|---|---|---|
| `/orca write a hello world script` | inline | current cc runs the workflow itself |
| `/orca refactor auth + add tests --workers 2` (in tmux, host=cc) | pane | host spawns 2 codex panes (default worker=codex), each with its own worktree |
| same as above but not in tmux | subagent | host calls cc Task tool ×2, blocks until both return |
| `/orca check this code --worker codex` (in tmux) | pane | one codex pane, one worktree |
| `/orca check this code --worker codex` (not in tmux) | error | "heterogeneous worker requires tmux" |

## Mode resolution

Top-down, first match wins:

```
if --mode given: use it (no auto resolution)

if workers == 1 AND worker == host:
    → inline

if worker MODEL ≠ host:
    if in tmux: → pane
    else:       → error "heterogeneous worker requires tmux"

if workers > 1:
    if in tmux: → pane
    else:       → subagent (degrade — see below)

→ inline
```

**Worker model never silently swaps** — if user said `--worker codex`, we never pick a different model just to make a mode work. Mode adapts to the model, not the other way around.

**Degradation visibility**: when subagent mode is selected because pane was unavailable (workers > 1 + not in tmux), `/orca` prints a one-line log to the user before dispatching:

```
[orca] no tmux detected — running 2 workers as subagents (no live visibility, ask me for status)
```

User can always query host agent ("what are workers doing?") since it owns the Task tool handles.

## Capability matrix

| Host | inline | subagent | pane |
|---|---|---|---|
| Claude Code | ✅ | ✅ Task tool | ✅ if in tmux |
| Codex | ✅ | ❌ no subagent primitive | ✅ if in tmux |

Codex host + parallelism asked + not in tmux → error. There is no fallback path; we tell the user to start tmux.

## Mode mechanics

### inline

The trivial case. `/orca <task>` body and host conversation are the same thing. Skill content describes the workflow steps; host agent reads and executes.

No spawning, no IPC, no worktree (host already has the repo checked out wherever it's running). Reports back to user inline.

### subagent

Host invokes the cc Task tool. One Task call per worker. The Task tool prompt embeds:
- the task body
- the workflow ("implement → /review → test → report")
- result contract: "return a summary of changes + test status"

Optional worktree: by default subagent inherits host's cwd. With multiple workers writing to overlapping files this conflicts; two paths:
- **Default** (workers ≤ 1): no worktree, subagent uses host cwd
- **workers > 1**: each subagent gets a worktree (`orca-worktree create <slug>` from host before Task call), Task prompt includes `cd <worktree>` instruction

cc Task tool runs synchronously per call. Multiple calls in the same assistant turn run in parallel (verify behavior — listed in Open). If parallel works, `--workers N` honored; if not, sequential with a warning.

No long-lived process, no socket, no separate tmux server — fully in cc's process.

### pane

The full multi-process case. Per-worker steps:

1. **Resolve tmux server**:
   - If host is already inside a `tmux -L orca-<basename(pwd)>` socket, reuse that socket (host is in an existing orca instance — likely from a previous `/orca` call this session).
   - Else: bring up fresh per-instance server `tmux -L orca-<basename(pwd)>` and migrate host pane into it (TODO confirm — see Open).
2. **Worktree**: `orca-worktree create <slug>` (default ON; `--no-worktree` skips). Slug = kebab-case feature derivative; multi-worker on same feature = `<slug>-<n>`. Auto-appends `.orca/` to host repo `.gitignore` if missing (existing behavior).
3. **Pane spawn**: `tmux split-window -t <orca-socket>` with `cd <worktree>` and launch worker binary (`cc` or `codex`) inside.
4. **Env injection** at spawn: `ORCA_PEER=<host-pane-id>` so worker knows where to push reports. **No `ORCA_ROLE`** — task arrival = role.
5. **Task delivery**:
   - **Short task** (≤ ~500 chars, no single quotes / newlines): wait for worker prompt to be ready (poll for ready signal — see Open), then `tmux-bridge message <pane> '<task body>'` + `tmux-bridge keys <pane> Enter`.
   - **Long task / multi-worker dispatch**: write `.orca/dispatches/<timestamp>/<slug>.md` (one file per worker, or one file with section per worker — host's choice), then paste pointer message:
     ```
     Read .orca/dispatches/20260422-153045/auth-refactor.md and execute the workflow described there.
     ```
   - This follows D10: short = inline; long = file. Keeps worker context lean and survives compaction.
6. **Pane label**: `tmux select-pane -t <pane> -T <slug>` so user sees worker name.

### Communication (pane mode only)

Worker → host on completion: **push + file** (Q5).

Worker writes report file:
```bash
report_path=".orca/reports/$(date +%Y%m%d-%H%M%S)-<slug>.md"
cat > "$report_path" <<'EOF'
## Worker: <slug>
## Status: done | failed | needs-input
## Summary: <1-2 sentences>
## Changes: <files touched>
## Tests: <pass/fail>
## Notes: <anything for lead>
EOF
```

Worker pushes notification:
```bash
tmux-bridge message $ORCA_PEER "Worker <slug> done — see $report_path"
tmux-bridge keys $ORCA_PEER Enter
```

Push lands in host's pane as user-visible text on next host tool call (cc behavior). File survives any context compaction and is auditable.

Bidirectional: workers can also initiate (e.g. ask lead to clarify) — same push+file pattern, just `status: needs-input` and host treats it as a question.

### Worker termination (pane mode)

After report sent, worker pane stays alive with the cc/codex prompt — does NOT auto-close. Reasoning:
- Lead may want to send follow-up ("also fix this", "rerun tests")
- Auto-close races with the push notification
- Cleanup is `orca stop` (kills the per-instance tmux server) or manual close

User can manually close panes anytime; `orca ps` shows live ones.

## `.orca/` filesystem layout

```
<repo>/.orca/
├── worktree/                     # existing — git worktrees per worker
│   ├── auth-refactor/
│   └── add-tests/
├── dispatches/                   # NEW — long task bodies for workers
│   └── 20260422-153045/
│       ├── auth-refactor.md
│       └── add-tests.md
└── reports/                      # NEW — worker reports back to lead
    ├── 20260422-153420-auth-refactor.md
    └── 20260422-153510-add-tests.md
```

Lifecycle: nothing is GC'd in v1. `worktree/` cleanup is manual (`orca-worktree clean`). `dispatches/` and `reports/` accumulate indefinitely — `.gitignore` keeps them out of git, disk impact negligible. Revisit if a real user complains.

## `orca` CLI surface

| Command | Status | Purpose |
|---|---|---|
| `orca ps` | keep | list per-instance tmux sockets + worker panes |
| `orca stop` | keep | tear down current dir's tmux server (cleans all worker panes) |
| `orca rm <name>` | keep | tear down a specific named instance |
| `orca prune` | keep | clean dead socket inodes |
| `orca doctor` | new | env check (tmux version, agent CLIs in PATH, hooks dir, etc.) |
| `orca hud` | new (later) | text dashboard à la OMX (deferred — not in this PR) |
| `orca-worktree {create,remove,list,clean}` | keep | worktree mgmt (called by skill, not user) |
| `tmux-bridge {read,message,list,keys}` | keep | IPC primitive (called by skill) |
| `orca` (start session) | **removed** | host agent owns orchestration |
| `orca idle` | removed | no heartbeat anymore |

## Removed (legacy)

| Thing | Why |
|---|---|
| `start.sh` | Host agent spawns panes itself when pane mode fires |
| `$ORCA_ROLE` / `$ORCA_WORKERS` env-var role detection | Worker spawn carries task in delivery, not env |
| SessionStart auto-fire of `/orca` | Entry is user-initiated; auto-fire was for the old `start.sh` flow |
| PostToolUse heartbeat hook | No heartbeat in v1 — push-driven only (re-add if real stuck cases appear) |
| PreToolUse idle check hook | Same as above |
| Fixed "1 lead + N worker" upfront layout | On-demand spawn per Q3 / D11 |
| `skills/workflows/code/SKILL.md` (separate dir) | Folded into `skills/orca/SKILL.md` (workflow = the skill) |
| `orca idle` CLI | No heartbeat to wait on |

## `install.sh` changes

| Action | Before | After |
|---|---|---|
| Symlink `~/.claude/skills/orca` → `skills/orca` | yes | yes (skill content rewritten) |
| Symlink `~/.claude/skills/orca-code` → `skills/workflows/code` | yes | **removed** (folded in) |
| Install PostToolUse / PreToolUse hooks to `~/.claude/settings.json` | yes | **removed** |
| Install `~/bin/{tmux-bridge,orca-worktree,orca}` | yes | yes |
| Append `eval "$(orca completions zsh)"` to shell rc | (n/a today) | (n/a) |
| Print "you can now run `orca` to start a session" | yes | **removed** — print "you can now use `/orca <task>` inside cc/codex" |
| Run `orca doctor` at end | (n/a today) | new |

Nesting guard: `install.sh` checks `$TMUX` and `$ORCA_*` env to avoid double-installing inside an already-orca'd shell — print a notice and skip.

## Implementation scope (single PR)

One PR covers everything (`one-shot per Q4-2`):

1. Rewrite `skills/orca/SKILL.md` (resolution logic + per-mode instructions; embeds workflow text from `skills/workflows/code/`)
2. Delete `skills/workflows/code/` directory
3. Add pane-spawn helper script (extracted from `start.sh`)
4. Add `orca doctor` subcommand
5. Update `install.sh` per table above
6. Delete `start.sh`
7. Delete `~/.claude/settings.json` hook entries (or leave install.sh idempotent to clean them on re-run)
8. Update `PLAN.md` (D11 already updated, Phase E0 sub-phases collapse to "single PR")
9. Update `README.md` / `README.zh-CN.md` quick-start (no more `orca` command, use `/orca <task>` inside cc)

## Open

1. **Subagent parallel semantics** — verify cc Task tool behavior when called multiple times in one assistant turn. If sequential, document `--workers N` in subagent mode as "sequential, with progress logged".
2. **Bringing host pane into orca tmux server** — when host cc is in a non-orca tmux (or no tmux) and pane mode fires, can we move the running cc process into a new tmux socket? `reptyr`-style. Likely no — fall back to "spawn new orca tmux session, ask user to attach manually, host stays where it is".
3. **Worker prompt-ready signal** — after `tmux split-window` launches `cc`/`codex`, how do we know the prompt is ready to accept a paste? Today: empirical sleep. Better: poll `tmux-bridge read` for prompt marker.
4. **`.orca/dispatches/` slug collision** — same timestamp + same slug if user double-fires `/orca`. Add `-<random>` suffix? Or trust ms-precision timestamp?
5. **Codex tmux-bridge paste reliability** — D10 noted Codex multi-line paste needs Enter×2 (timing-sensitive). For long-task pointer message (single line), should be fine; verify in pane mode with codex worker.
