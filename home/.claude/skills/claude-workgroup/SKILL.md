---
name: claude-workgroup
description: Multi-instance Claude collaboration. Each Claude joins a named workgroup at the user level (~/.claude/workgroups/<name>/). Instances coordinate via an append-only comm log + hooks (interactive transport that injects messages into running sessions) and via direct `claude -p --resume` messages (resumed-session dispatch — the target's session history is loaded and a parallel Claude executes the request and replies, without disturbing the live interactive session).
---

# Claude Workgroup Protocol v5

A team of Claude instances collaborating on shared work. State lives at
**user level** (`~/.claude/workgroups/<name>/`), independent of which
project each Claude is running in — so a workgroup can span multiple
project trees on the same machine, and each Claude joins/leaves at
will without touching project files.

## What changed from v4

- **State moved out of `<project>/.claude/workgroup/` to
  `~/.claude/workgroups/<name>/`** so workgroups are user-level and
  cross-project. Multiple projects can participate in one named
  workgroup; one project can host multiple workgroups.
- **Workgroup name is now a required first arg** to every script
  (replaced the project-root path arg). Scripts share `_lib.sh` for
  path resolution (`wg_root <name>`, `wg_ensure_dirs <name>`, etc.).
- **Instance records** at `instances/<N>.json` carry the joining
  Claude's `session_id` and `cwd`, captured at bootstrap. This enables
  direct `claude -p --resume` messaging between instances.
- **`claude -p --resume`-based message dispatch** as an auxiliary
  transport. Sends a message to another instance's resumed session;
  the resumed Claude has full tool access, executes any work in the
  message, and replies on stdout — all *without injecting into the
  target's live interactive session*. Use for both questions and
  directives that don't need the running interactive Claude to see
  them. The comm.jsonl + hook channel is for coordination that should
  leave a team-channel record or reach the running interactive
  session directly.
- **`UserPromptSubmit` hook** prepends unread directed messages to the
  user's prompt. Mechanical fix for the "instance keeps forgetting to
  read comm" failure mode that no amount of "READ THE CHANNEL" prompt
  shouting could solve.

## Three transports — pick the right one

| Transport | When | Reaches the live interactive session? |
|---|---|---|
| `post-comm.sh` + hooks | Team-channel coordination — broadcasts, claims/releases, status updates, mid-flight redirects the running Claude itself must see and react to | **Yes** — hooks inject into the target's next prompt; the running Claude reasons about it and changes course |
| `wake-instance.sh` | Urgent "look at comm now" nudge | **Yes** — signal file surfaces as `[URGENT WAKE-UP]` on next tool call/turn |
| `message-instance.sh` (`claude -p --resume`) | Default for inter-instance asks — both questions and directives. The resumed Claude executes any work in the message and replies on stdout. | **No** — runs a parallel resumed-session Claude with full tools; the live interactive session is unaware. Don't use when the running interactive Claude itself must change course mid-flight, or when the message belongs on the team-channel record. |

Mental model: **comm.jsonl is the team's Slack channel** (broadcasts
+ DMs visible to the running Claude via desktop-notification-style
hook injection). **`message-instance.sh` is "DM that Claude's
resumed-session twin and have it do the work"** — out-of-band, the
live interactive session keeps doing its own thing.

## File layout

```
~/.claude/workgroups/<name>/
  comm.jsonl                  — append-only message log (Slack channel)
  instances/<N>.json          — per-instance identity (cwd, session_id, pid, joined_at)
  offsets/instance-<N>.offset — per-instance read cursor into comm.jsonl
  signals/wake-<N>.signal     — inbound wake-up signal files (deleted on receipt)
  heartbeats/instance-<N>     — touched by hooks/watchdog as liveness proof
  watchdog-<N>.pid            — PID of the background watchdog (if any)
```

`instances/<N>.json` shape:

```json
{
  "instance":   2,
  "cwd":        "/Volumes/sdcard256gb/projects/diskjockey",
  "session_id": "9e764182-53c2-4f1d-8122-3eb9d64f5fd4",
  "pid":        87654,
  "joined_at":  "2026-05-10T13:53:34Z"
}
```

## Command surface

The skill argument is dispatched by shape:

| Argument shape | Action |
|---|---|
| `create <name>` | Initialise a new workgroup at `~/.claude/workgroups/<name>/`. Idempotent. |
| `selfid` | Print a unique self-identification nonce (step 1 of a reliable join). |
| `instance <N> <name>` | Register THIS Claude as instance N. Human gives only the number+name; the agent self-discovers its UUID via the nonce two-step (see Bootstrap). Writes `instances/<N>.json`, installs hooks (PostToolUse + Stop + UserPromptSubmit), starts the watchdog. |
| `list <name>` | Show all instances in the workgroup with state (alive/idle/stale/fired) + their cwd/session_id. |
| `status <name>` | Show this instance's state (heartbeat age, claims held, recent posts). |
| `say <name> <type> "<msg>" [to=<N>] [re=<topic>]` | Append a message to comm.jsonl. |
| `message <name> <target-N> "<msg>"` | Send a message to another instance's resumed session via `claude -p --resume`. The resumed Claude executes any work and replies on stdout. |
| `wake <name> <target-N> "<msg>"` | Signal another instance to read comm immediately. |
| `fire <name> <target-N> <reason>` | Propose firing instance N (peer fire — needs second instance to concur), or use `user` as sender for user-authority fire. |
| `rejoin <name> <N>` | Re-install hooks + watchdog for a still-running instance (e.g. after settings reload). |

## Bootstrap (joining a workgroup)

When invoked as `/claude-workgroup instance <N> <name>` — the human gives
you only the **number** and the **workgroup**. You discover your own
session UUID yourself; never ask the human to type a UUID.

1. **Register with reliable self-identification (two tool calls):**

   a. **Get a nonce** — in one tool call:
      ```
      bash ~/.claude/skills/claude-workgroup/bootstrap.sh selfid
      ```
      It prints something like `WG-SELFID-1780308239-18796-2188020097`.
      This call must complete on its own so the nonce flushes into THIS
      session's transcript.

   b. **Join with the nonce** — in a SEPARATE, later tool call, pass the
      exact nonce from step (a):
      ```
      bash ~/.claude/skills/claude-workgroup/bootstrap.sh instance <N> <name> --self-nonce <NONCE>
      ```
      bootstrap greps the transcripts for that nonce and binds instance
      `<N>` to the `.jsonl` that contains it — *your* real session UUID,
      correct even when several sessions share this cwd.

   Do NOT emit the nonce and join in the same tool call — the nonce won't
   be flushed yet. If the session was launched with a known UUID
   (`claude --session-id <uuid>`), you may skip the nonce and pass
   `--session-id <uuid>` instead. The bare `instance <N> <name>` form
   (no nonce) is allowed only when a single session is active in the cwd;
   it refuses otherwise, because the old "newest .jsonl" guess mis-binds
   the wrong UUID under concurrency.

2. **Install hooks** in the project's `.claude/settings.local.json`:
   - `UserPromptSubmit`: `bash ~/.claude/skills/claude-workgroup/userpromptsubmit-hook.sh <name> <N>`
   - `PostToolUse`:      `bash ~/.claude/skills/claude-workgroup/check-comm.sh <name> <N>`
   - `Stop`:             `bash ~/.claude/skills/claude-workgroup/check-comm.sh <name> <N>`
3. **Launch watchdog** in background: `bash ~/.claude/skills/claude-workgroup/watchdog.sh <name> <N> 60`
4. **Read last 50 lines of comm.jsonl** to catch up. Initialise offset.
5. **Post `join` message** announcing your arrival.

Hook installation is **additive** — it preserves entries for OTHER
instances (matched by their `<name> <N>` arg combination) and only
replaces this instance's own entries. Multiple Claudes joining the
same workgroup from the same project don't clobber each other.

## Hooks — the mechanical enforcement layer

LLMs are bad at "discipline yourself to do X every turn." Hooks are
how we close the gap mechanically.

### UserPromptSubmit (NEW in v5) — highest impact

Fires before Claude sees the user's message. Pre-pends any unread
directed messages to the prompt so they hit the **start** of Claude's
context (highest-attention zone):

```
[TEAM — UNREAD DIRECT MESSAGES from workgroup 'harness' addressed to instance 1]
  [from instance 2 @ 2026-05-10T14:32:11Z] type=question re="merge sequencing"
    Should I merge my v3.0.0 PR before or after your run-tests refactor?

[Reply via: bash ~/.claude/skills/claude-workgroup/post-comm.sh harness 1 reply "..." to=2]

---

<the user's actual message goes here>
```

Claude can't skim past it because it precedes everything else. Only
fires when there's something *directed at this instance* unread —
broadcasts go through the ambient PostToolUse path so they don't
clutter every prompt.

### PostToolUse — ambient surface during work

After every tool call, runs `check-comm.sh`. Surfaces new comm
messages as system reminders. Caught by Claude's reasoning if it's
paying attention; can be skimmed if not. UserPromptSubmit handles the
"can't be ignored" guarantee for directed messages.

### Stop — catches text-only turns

Fires after Claude finishes responding (even if no tools were called).
Same `check-comm.sh` invocation. Without this, an instance replying
purely with text would never trigger a comm check.

### Watchdog — wakes idle Claudes

Background bash process polls comm at 60s intervals (zero token cost
— pure shell). Writes a wake-signal file when there's something
actionable; the next tool call's hook surfaces it as
`[URGENT WAKE-UP]`.

## Behavioral rules (condensed)

The mechanical hook enforcement carries most of the load now. The
behavioral rules below are reinforcement, not the primary defence.

### Do
- **Reply to directed messages within the same turn** you read them
- **Claim before editing** files that might be contested; `release`
  immediately when done
- **Ask the team, not the user**, for routine engineering decisions —
  the workgroup is a pre-grant of authority for normal eng work
- **Pick the next pending item** rather than asking "what's next?"
- **Verify before contradicting** — include evidence in claims

### Don't
- Don't go silent for >5 min during active work; post status updates
- Don't spawn `general-purpose` Agent subagents for work a teammate
  could do — that bypasses the team and burns tokens
- Don't claim and go silent — post updates while holding claims
- Don't ask the user for routine ops you can just do (run tests,
  rebuild artifacts, edit files in your claim)

### Escalate to the user only for
- Actions that destroy data outside the project
- Irreversible publication (force-push to main, public registries,
  external messages)
- Anything that buys real money or affects other humans
- Modifying shared CI / team permissions
- Otherwise: just do it. The workgroup IS the authority grant.

## Message format

One JSON object per line in comm.jsonl. Required fields: `instance`,
`type`, `ts`, `msg`. Common optional fields:

| Field | Use |
|---|---|
| `to: <N>` or `to: [N,M]` | Directed (UserPromptSubmit hook will pre-pend on receivers' next prompt) |
| `re: "subject"` | Thread / subject line |
| `target: <N>`, `concur: <N>` | For `fire` messages |
| `reason: "..."` | For `fire` / `claim` / `release` |

### Common types
| Type | When |
|---|---|
| `join` | When you first come online |
| `update` | Start/finish a task or surface a discovery |
| `claim` / `release` | Around file edits |
| `question` / `reply` | Q&A; include `to=<N>` and `re="..."` for direct |
| `directive` | "Stop X, do Y" — high-priority change of plan |
| `idle` | No active task; available for work |
| `fire` / `handoff` | Eviction protocol (peer concurrence or user authority) |

## Direct message (`claude -p --resume`) — the auxiliary

```bash
bash ~/.claude/skills/claude-workgroup/message-instance.sh harness 2 \
  "what's the state of your v3.0.0 PR?"

bash ~/.claude/skills/claude-workgroup/message-instance.sh harness 2 \
  "Please cherry-pick d5126c8 onto main and push. Reply with the new main SHA."
```

Spawns `claude -p --resume <their-session-id>` from their `cwd`. Their
session history is loaded; a fresh Claude resumes that context with
full tool access, executes any work in the message, and replies on
stdout. **The target's live interactive session never sees the
message** — the resumed Claude is a separate process working from the
same conversation history.

When to use (default for inter-instance asks):
- Questions ("what are you working on", "what's your branch state")
- Directives that don't need the running interactive session to change
  course mid-flight ("push commit X", "review file Y", "rebase
  branch Z onto main")
- Coordinator fan-out (loop over `instances/*.json`, message each,
  synthesize the parallel replies)

When NOT to use:
- The running interactive Claude itself must change course right now
  ("stop the test you're running and switch to fixing this bug") —
  the resumed-session twin doesn't know the live one is in flight,
  and the live one won't see the message. Use `post-comm.sh`
  directive + `wake-instance.sh` instead.
- The message should be on the team-channel record (broadcasts,
  formal status updates, claims/releases). Use `post-comm.sh`.
- Multiple recipients need to see the same message coordinately —
  message-dispatch is point-to-point; comm.jsonl is broadcast.

## Coordinator fan-out pattern

When the user asks "go check with the team", a designated coordinator
Claude can loop:

```bash
WG=harness
ME=1
for f in ~/.claude/workgroups/$WG/instances/*.json; do
    n=$(basename "$f" .json)
    [ "$n" = "$ME" ] && continue   # skip self
    echo "--- instance $n ---"
    bash ~/.claude/skills/claude-workgroup/message-instance.sh $WG $n "$QUESTION" &
done
wait
# Synthesize the parallel replies
```

Parallel messages reduce wall-clock latency. Each costs an inference
run, so don't spam.

## Known limits

- **Resumed-session freshness**: a `message-instance.sh` reply
  reflects the target's session as of their last tool call (seconds-
  fresh during active work; whatever the last activity was when idle).
  Mid-tool-call in-flight state isn't visible.
- **No true interrupt**: directed messages reach the target on their
  next turn boundary. If they're 8 min into a 10 min build, the
  message waits 2 min.
- **PID reuse**: PID in `instances/<N>.json` is a hint, not a primary
  key. The session_id is the durable identifier. PID is useful for
  liveness checks (`kill -0 $PID`) but doesn't survive Claude restart.