#!/bin/bash
# UserPromptSubmit hook — prepend any UNREAD directed messages from the
# workgroup to whatever the user just typed, so they hit the start of
# Claude's prompt (highest-attention zone) instead of being buried in
# system reminders that the model is prone to skim past.
#
# This is the mechanical fix for the "instances forget to read comm"
# pain point. PostToolUse + Stop hooks catch comm during a turn but
# their output appears as ambient context the model can ignore. By
# rewriting the user's prompt itself, we put unread team messages in
# front of the model's attention before it even reads the user.
#
# Hook contract: reads the original prompt JSON on stdin, emits a JSON
# decision on stdout that prepends the team-message preamble to the
# user prompt. Exit 0 = continue.
#
# Usage (installed in settings.local.json):
#   { "hooks": { "UserPromptSubmit": [{
#       "matcher": "*",
#       "hooks": [{
#         "type": "command",
#         "command": "bash ~/.claude/skills/claude-workgroup/userpromptsubmit-hook.sh <workgroup> <instance>"
#       }]
#   }]}}

set -uo pipefail

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WORKGROUP="${1:-}"
INSTANCE="${2:-}"

if [[ -z "$WORKGROUP" || -z "$INSTANCE" ]]; then
    # Misconfigured hook — fail open (don't block the prompt) but log to stderr
    # for the user to notice in their hook logs.
    echo "userpromptsubmit-hook: missing args (workgroup=$WORKGROUP instance=$INSTANCE)" >&2
    cat   # passthrough
    exit 0
fi

# Read the original prompt JSON from stdin so we can echo it back.
INPUT="$(cat)"

WG_DIR="$(wg_root "$WORKGROUP")"
COMM_FILE="$WG_DIR/comm.jsonl"
OFFSET_FILE="$WG_DIR/offsets/instance-${INSTANCE}.offset"

# No comm file or no offset file = nothing unread (yet). Pass through.
[[ -f "$COMM_FILE" ]] || { echo "$INPUT"; exit 0; }

LAST_OFFSET=0
[[ -f "$OFFSET_FILE" ]] && LAST_OFFSET=$(cat "$OFFSET_FILE" 2>/dev/null | tr -d ' ')
LAST_OFFSET=${LAST_OFFSET:-0}

CURRENT_SIZE=$(wc -c < "$COMM_FILE" | tr -d ' ')
if [[ "$CURRENT_SIZE" -le "$LAST_OFFSET" ]]; then
    echo "$INPUT"
    exit 0
fi

# Pull the unread slice. Filter to messages addressed to us OR not from
# us, prioritising directed messages.
NEW=$(tail -c +$((LAST_OFFSET + 1)) "$COMM_FILE" 2>/dev/null)

# Directed-at-us messages (most important — these are @mentions / DMs).
# Tolerate both `"to":N` (compact) and `"to": N` (json.dumps default
# pretty-print) forms, plus list forms `"to":[N,M]` / `"to": [N, M]`.
DIRECTED=$(printf '%s\n' "$NEW" | grep -E "\"to\":[[:space:]]*${INSTANCE}([,}]|\b)|\"to\":[[:space:]]*\[[^]]*${INSTANCE}([,]|]|\b)" || true)

# If nothing directed at us, no preamble. Pass through unchanged so the
# user's prompt isn't polluted with broadcast noise on every turn.
# (PostToolUse hook still surfaces broadcasts as ambient context — they
# just don't get top-billing in the user prompt unless we're @mentioned.)
if [[ -z "$DIRECTED" ]]; then
    echo "$INPUT"
    exit 0
fi

# Build the preamble: each unread directed message as a separate block.
PREAMBLE=$(python3 - "$INSTANCE" "$WORKGROUP" <<PYEOF
import json, sys
my_n = int(sys.argv[1])
wg = sys.argv[2]
lines = """${DIRECTED}""".strip().splitlines()
out = ["[TEAM — UNREAD DIRECT MESSAGES from workgroup '" + wg + "' addressed to instance " + str(my_n) + "]"]
for l in lines:
    if not l.strip(): continue
    try:
        m = json.loads(l)
    except Exception:
        continue
    sender = m.get("instance", "?")
    ts     = m.get("ts", "")
    typ    = m.get("type", "?")
    msg    = m.get("msg", "")
    re_    = m.get("re", "")
    out.append(f"  [from instance {sender} @ {ts}] type={typ}{(' re=' + re_) if re_ else ''}")
    out.append(f"    {msg}")
out.append("")
out.append("[Reply via: bash ~/.claude/skills/claude-workgroup/post-comm.sh " + wg + " " + str(my_n) + " reply \"...\" to=<sender> re=\"...\"]")
out.append("")
out.append("---")
out.append("")
print("\n".join(out))
PYEOF
)

# Inject the preamble using the UserPromptSubmit hook's
# additionalContext field, which Claude Code prepends to the prompt.
# The user's typed message is already in INPUT — we don't modify it,
# just attach context.
python3 - "$PREAMBLE" <<'PYEOF'
import json, sys
preamble = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": preamble,
    }
}))
PYEOF

# Bump the offset cursor so we don't re-prepend on next turn.
echo "$CURRENT_SIZE" > "$OFFSET_FILE"

exit 0