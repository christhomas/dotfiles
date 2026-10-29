#!/bin/bash
# claude-workgroup cron tick (option C: report state, let Claude decide).
#
# Called by a per-instance cron every minute. Outputs a brief status summary
# that Claude reads and decides whether to act on.
#
# Output format (for Claude to parse):
#   [TICK instance=N project=... ts=...]
#   HEARTBEAT: touched
#   SIGNAL: <present|none>
#   FIRE: <present|none>
#   DIRECTED: <count>
#   URGENT_HELP: <count>
#   STALE_PEERS: <list of instance numbers with stale heartbeats>
#   ACTION_NEEDED: <yes|no>
#
# Usage: cron-tick.sh <workgroup> <instance>

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WORKGROUP="${1:?Usage: cron-tick.sh <workgroup> <instance>}"
INSTANCE="${2:?Usage: cron-tick.sh <workgroup> <instance>}"

WG_DIR="$(wg_root "$WORKGROUP")"
wg_ensure_dirs "$WORKGROUP"

COMM_FILE="$WG_DIR/comm.jsonl"
OFFSET_FILE="$WG_DIR/offsets/instance-${INSTANCE}.offset"
SIGNAL_FILE="$WG_DIR/signals/wake-${INSTANCE}.signal"
HEARTBEAT_FILE="$WG_DIR/heartbeats/instance-${INSTANCE}"

touch "$HEARTBEAT_FILE" 2>/dev/null

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "[TICK workgroup=$WORKGROUP instance=$INSTANCE ts=$TS]"
echo "HEARTBEAT: touched"

# Signal file
if [ -f "$SIGNAL_FILE" ]; then
    echo "SIGNAL: present"
    echo "  CONTENT: $(cat "$SIGNAL_FILE" 2>/dev/null | head -c 300)"
else
    echo "SIGNAL: none"
fi

# Fire notice — check comm for fire targeting us with concurrence
FIRE_NOTICE=""
if [ -f "$COMM_FILE" ]; then
    # Look for {"type":"fire","target":N,...} in last 200 lines
    FIRE_ME=$(tail -200 "$COMM_FILE" 2>/dev/null | grep "\"type\":\"fire\"" | grep "\"target\":$INSTANCE")
    if [ -n "$FIRE_ME" ]; then
        # Need at least one concur OR a user-override (reason contains "[user]")
        CONCUR=$(echo "$FIRE_ME" | grep "\"concur\"")
        USER_FIRE=$(echo "$FIRE_ME" | grep "\[user\]")
        if [ -n "$CONCUR" ] || [ -n "$USER_FIRE" ]; then
            FIRE_NOTICE="$FIRE_ME"
        fi
    fi
fi

if [ -n "$FIRE_NOTICE" ]; then
    echo "FIRE: present"
    echo "  CONTENT: $(echo "$FIRE_NOTICE" | head -1 | head -c 400)"
else
    echo "FIRE: none"
fi

# Directed messages (since last offset)
DIRECTED_COUNT=0
URGENT_HELP=0
if [ -f "$COMM_FILE" ] && [ -f "$OFFSET_FILE" ]; then
    OFFSET=$(cat "$OFFSET_FILE" 2>/dev/null | tr -d ' ')
    OFFSET=${OFFSET:-0}
    NEW=$(tail -c +$((OFFSET + 1)) "$COMM_FILE" 2>/dev/null)
    if [ -n "$NEW" ]; then
        DIRECTED_COUNT=$(echo "$NEW" | grep -c "\"to\":$INSTANCE\|\"to\":\[.*$INSTANCE" 2>/dev/null | head -1 | tr -d ' ')
        URGENT_HELP=$(echo "$NEW" | grep -ci "WAKE UP\|STUCK\|HELP\|urgent" 2>/dev/null | head -1 | tr -d ' ')
        DIRECTED_COUNT=${DIRECTED_COUNT:-0}
        URGENT_HELP=${URGENT_HELP:-0}
    fi
fi
echo "DIRECTED: $DIRECTED_COUNT"
echo "URGENT_HELP: $URGENT_HELP"

# Stale peers: any heartbeat older than 30 min belonging to another instance
STALE_PEERS=""
NOW=$(date +%s)
for hb in "$WG_DIR/heartbeats/"instance-*; do
    [ -f "$hb" ] || continue
    peer=$(basename "$hb" | sed 's/instance-//')
    [ "$peer" = "$INSTANCE" ] && continue
    mtime=$(stat -f %m "$hb" 2>/dev/null || echo 0)
    age=$((NOW - mtime))
    if [ "$age" -gt 1800 ]; then  # 30 min
        STALE_PEERS="$STALE_PEERS $peer(${age}s)"
    fi
done
echo "STALE_PEERS:${STALE_PEERS:- none}"

# Decide if action is needed
if [ -f "$SIGNAL_FILE" ] || [ -n "$FIRE_NOTICE" ] || [ "$DIRECTED_COUNT" -gt 0 ] || [ "$URGENT_HELP" -gt 0 ]; then
    echo "ACTION_NEEDED: yes"
else
    echo "ACTION_NEEDED: no"
fi
