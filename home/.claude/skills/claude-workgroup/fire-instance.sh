#!/bin/bash
# Fire (remove) an instance from the workgroup.
#
# Modes:
#   Peer fire: one instance proposes, another must concur (2-of-N rule).
#   User fire: bypasses concurrence (--user flag adds "[user]" marker to reason).
#
# Usage:
#   fire-instance.sh <workgroup> <sender-instance> <target-instance> "<reason>"  (peer)
#   fire-instance.sh <workgroup> user <target-instance> "<reason>"               (user)

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WORKGROUP="${1:?Usage: fire-instance.sh <workgroup> <sender|user> <target> <reason>}"
SENDER="${2:?Usage: fire-instance.sh <workgroup> <sender|user> <target> <reason>}"
TARGET="${3:?Usage: fire-instance.sh <workgroup> <sender|user> <target> <reason>}"
shift 3
REASON="$*"

wg_ensure_dirs "$WORKGROUP"
COMM_FILE="$(wg_root "$WORKGROUP")/comm.jsonl"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$SENDER" = "user" ]; then
    # User-authority fire — bypasses concurrence. Use instance:0 to mark user origin.
    echo "{\"instance\":0,\"type\":\"fire\",\"target\":${TARGET},\"reason\":\"[user] ${REASON}\",\"ts\":\"${TS}\"}" >> "$COMM_FILE"
    echo "User fire posted for instance $TARGET. Takes effect immediately."
else
    # Peer fire — proposes, needs concur from another instance
    # Check if this is an initial proposal or a concurrence
    EXISTING=$(grep "\"type\":\"fire\",\"target\":$TARGET" "$COMM_FILE" 2>/dev/null | grep -v "\"concur\"" | head -1)
    if [ -n "$EXISTING" ]; then
        # Get the original proposer
        PROPOSER=$(echo "$EXISTING" | grep -oE '"instance":[0-9]+' | head -1 | grep -oE '[0-9]+')
        if [ "$PROPOSER" = "$SENDER" ]; then
            echo "You already proposed firing instance $TARGET. Another instance must concur."
            exit 1
        fi
        # Post as concurrence
        echo "{\"instance\":${SENDER},\"type\":\"fire\",\"target\":${TARGET},\"concur\":${PROPOSER},\"reason\":\"${REASON}\",\"ts\":\"${TS}\"}" >> "$COMM_FILE"
        echo "Concurrence posted. Instance $TARGET is now fired (proposer=$PROPOSER, concurrer=$SENDER)."
    else
        # New proposal
        echo "{\"instance\":${SENDER},\"type\":\"fire\",\"target\":${TARGET},\"reason\":\"${REASON}\",\"ts\":\"${TS}\"}" >> "$COMM_FILE"
        echo "Fire proposal posted for instance $TARGET. Awaiting concurrence from another instance."
    fi
fi
