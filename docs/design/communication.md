# Communication Design

How agents talk to each other in Orca.

## Layers

```
Lead ←→ Worker communication

┌─────────────────────────────────────────────┐
│  Skill layer (SKILL.md)                     │  — what to say
│  "dispatch task, report result"             │
├─────────────────────────────────────────────┤
│  tmux-bridge layer (smux)                   │  — how to say it
│  read → message → read → keys Enter        │
├─────────────────────────────────────────────┤
│  tmux layer                                 │  — transport
│  send-keys / capture-pane / pane buffers    │
└─────────────────────────────────────────────┘
```

## tmux-bridge Protocol

All communication uses a single `&&`-chained command:

```bash
tmux-bridge read $ORCA_PEER 5 && \
tmux-bridge message $ORCA_PEER "msg" && \
tmux-bridge read $ORCA_PEER 5 && \
tmux-bridge keys $ORCA_PEER Enter
```

Why this pattern:
1. `read` first — wait for peer's pane to be ready (Read Guard)
2. `message` — type the text into peer's input
3. `read` again — wait for text to appear
4. `keys Enter` — submit the message

**Read Guard**: prevents sending to a pane that's busy or hasn't rendered yet.
Without it, keystrokes can arrive mid-output and get garbled.

## Short vs Long Messages

### Short tasks: inline

For tasks describable in a few lines, send inline:

```bash
tmux-bridge message <worker> "Task: add retry logic to api.py
Scope: src/api.py
Criteria: exponential backoff, max 3 retries
When done: /review, build, test, then report back."
```

### Long tasks: handoff file

tmux-bridge messages are ultimately `tmux send-keys` — long messages risk:
- **Truncation**: tmux paste buffer has limits
- **Garbling**: if the receiver's input buffer can't absorb fast enough
- **Lost on restart**: if worker crashes/restarts, the inline message is gone
- **Lost on compaction**: if lead's context compacts, it can't re-send the original

Solution: write the plan to a file, send only the path.

```bash
# Lead writes the full plan
plan_path="/tmp/orca-handoff-auth-refactor-$(date +%s).md"
cat > "$plan_path" <<EOF
## Task: Auth Middleware Refactor

### Context
The current auth middleware at src/middleware/auth.py uses...
[full context, 50+ lines]

### Scope
- src/middleware/auth.py
- src/middleware/session.py
- tests/test_auth.py

### Constraints
- Must maintain backwards compatibility with v2 API
- Session tokens must comply with new compliance requirements
...
EOF

# Lead sends only the pointer
tmux-bridge message <worker> "Read $plan_path and execute.
Worktree: cd $worktree_path
When done: /review, build, test, then report back."
```

**Why `/tmp`**:
- Zero repo intrusion (no `.gitignore` change)
- Survives tmux-bridge failures and worker restarts
- Auto-cleaned on reboot
- Worker reads the file via Read tool — standard, works across all agents

**When to use handoff files** — lead's judgment, not a hard threshold:
- Task description > ~10 lines
- Multiple files with specific change requirements
- Complex constraints or context needed
- Tasks where re-dispatch on failure is likely

## Heartbeat (Idle Detection)

Complementary to direct message communication. See [heartbeat.md](heartbeat.md).

## Multi-Worker Addressing

With multiple workers, lead must address specific workers:

```bash
# $ORCA_WORKERS = "orca-myproj-worker-1,orca-myproj-worker-2,orca-myproj-worker-3"

# Send to specific worker
tmux-bridge message orca-myproj-worker-2 "Your task: ..."

# $ORCA_PEER always points to worker-1 (backwards compat)
tmux-bridge message $ORCA_PEER "Your task: ..."
```

Workers always address lead via `$ORCA_PEER` (which points to the lead label).
