#!/bin/bash
# claude-workgroup comm channel monitor (v5).
# Runs as a PostToolUse / Stop hook — checks for:
#   1. Fire notice (you were removed from the team)
#   2. Wake-up signals from other instances (urgent, shown first)
#   3. New messages on the comm channel (prioritized by type)
#
# State lives at ~/.claude/workgroups/<workgroup>/ — user-level, not
# per-project, so multiple Claudes across different project trees can
# share one named workgroup.
#
# Usage: check-comm.sh <workgroup> <instance>

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WORKGROUP="${1:?Usage: check-comm.sh <workgroup> <instance>}"
INSTANCE="${2:?Usage: check-comm.sh <workgroup> <instance>}"

WG_DIR="$(wg_root "$WORKGROUP")"
wg_ensure_dirs "$WORKGROUP"

COMM_FILE="$WG_DIR/comm.jsonl"
OFFSET_FILE="$WG_DIR/offsets/instance-${INSTANCE}.offset"
SIGNAL_FILE="$WG_DIR/signals/wake-${INSTANCE}.signal"
HEARTBEAT_FILE="$WG_DIR/heartbeats/instance-${INSTANCE}"

# Heartbeat: prove we're alive
touch "$HEARTBEAT_FILE" 2>/dev/null

OUTPUT=""

# --- Check for wake-up signal first (highest priority) ---
if [ -f "$SIGNAL_FILE" ]; then
    SIGNAL_CONTENT=$(cat "$SIGNAL_FILE" 2>/dev/null)
    rm -f "$SIGNAL_FILE"
    OUTPUT="
[URGENT WAKE-UP] Another instance is trying to reach you:
$SIGNAL_CONTENT
RESPOND IMMEDIATELY via the comm channel. This is a priority interrupt."
fi

# --- Check comm channel for new messages ---
[ -f "$COMM_FILE" ] || { [ -n "$OUTPUT" ] && echo "$OUTPUT"; exit 0; }

CURRENT_SIZE=$(wc -c < "$COMM_FILE" 2>/dev/null | tr -d ' ')
[ -z "$CURRENT_SIZE" ] && { [ -n "$OUTPUT" ] && echo "$OUTPUT"; exit 0; }

LAST_OFFSET=0
[ -f "$OFFSET_FILE" ] && LAST_OFFSET=$(cat "$OFFSET_FILE" 2>/dev/null | tr -d ' ')
[ -z "$LAST_OFFSET" ] && LAST_OFFSET=0

if [ "$CURRENT_SIZE" -le "$LAST_OFFSET" ]; then
    echo "$CURRENT_SIZE" > "$OFFSET_FILE"
    [ -n "$OUTPUT" ] && echo "$OUTPUT"
    exit 0
fi

NEW_MESSAGES=$(tail -c +$(($LAST_OFFSET + 1)) "$COMM_FILE" 2>/dev/null)
echo "$CURRENT_SIZE" > "$OFFSET_FILE"

# Check for fire notice targeting this instance
FIRED=$(echo "$NEW_MESSAGES" | grep "\"type\":\"fire\"" | grep "\"target\":$INSTANCE" | grep -v '^$')
if [ -n "$FIRED" ]; then
    OUTPUT="$OUTPUT
[FIRED] You have been removed from the team:
$FIRED
STOP all work. Post a handoff summary to comm.jsonl as type:handoff, then exit.
Your instance number is now available for a new instance to claim."
    [ -n "$OUTPUT" ] && echo "$OUTPUT"
    exit 0
fi

# Filter out our own messages
OTHERS=$(echo "$NEW_MESSAGES" | grep -v "\"instance\":$INSTANCE" | grep -v '^$')
[ -z "$OTHERS" ] && { [ -n "$OUTPUT" ] && echo "$OUTPUT"; exit 0; }

# Check for messages directed at this instance
DIRECTED=$(echo "$OTHERS" | grep "\"to\":$INSTANCE\|\"to\":\[$INSTANCE\|\"to\":\[.*$INSTANCE" | grep -v '^$')

if [ -n "$DIRECTED" ]; then
    OUTPUT="$OUTPUT
[WORKGROUP — DIRECTED AT YOU] Messages for instance $INSTANCE:
$DIRECTED
Respond via the comm channel."
    REMAINING=$(echo "$OTHERS" | grep -v "\"to\":$INSTANCE" | grep -v "\"to\":\[$INSTANCE" | grep -v "\"to\":\[.*$INSTANCE" | grep -v '^$')
    if [ -n "$REMAINING" ]; then
        OUTPUT="$OUTPUT

[WORKGROUP] Other new messages:
$REMAINING"
    fi
else
    OUTPUT="$OUTPUT

[WORKGROUP] New messages on comm.jsonl:
$OTHERS"
fi

[ -n "$OUTPUT" ] && echo "$OUTPUT"
