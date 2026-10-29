#!/bin/bash
# List all workgroup instances and their status.
# Usage: list-instances.sh <workgroup>

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WORKGROUP="${1:?Usage: list-instances.sh <workgroup>}"
WG_DIR="$(wg_root "$WORKGROUP")"
wg_ensure_dirs "$WORKGROUP"
COMM_FILE="$WG_DIR/comm.jsonl"
NOW=$(date +%s)

echo "=== Claude Workgroup Status ==="
echo "Workgroup: $WORKGROUP"
echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Collect all known instance numbers from instance records, heartbeats,
# offsets, and recent comm.
declare -a KNOWN
for f in "$WG_DIR/instances/"*.json "$WG_DIR/heartbeats/"instance-* "$WG_DIR/offsets/"instance-*.offset; do
    [ -e "$f" ] || continue
    case "$f" in
        */instances/*.json) n=$(basename "$f" .json) ;;
        *)                  n=$(basename "$f" | sed -E 's/^instance-([0-9]+)(\..*)?$/\1/') ;;
    esac
    [[ "$n" =~ ^[0-9]+$ ]] && KNOWN+=("$n")
done

# Also scan recent comm messages for instance numbers
if [ -f "$COMM_FILE" ]; then
    RECENT=$(tail -200 "$COMM_FILE" | grep -oE '"instance":[0-9]+' | grep -oE '[0-9]+' | sort -u)
    for n in $RECENT; do
        KNOWN+=("$n")
    done
fi

# Dedupe
INSTANCES=$(printf '%s\n' "${KNOWN[@]}" | sort -n -u)

printf "%-5s %-10s %-15s %-15s %s\n" "N" "STATE" "HEARTBEAT_AGE" "LAST_MSG_AGE" "LAST_ACTIVITY"
printf "%-5s %-10s %-15s %-15s %s\n" "-" "-----" "-------------" "------------" "-------------"

for N in $INSTANCES; do
    HB="$WG_DIR/heartbeats/instance-$N"
    # Heartbeat age
    if [ -f "$HB" ]; then
        HB_MTIME=$(stat -f %m "$HB" 2>/dev/null)
        HB_AGE=$((NOW - HB_MTIME))
        HB_AGE_STR="${HB_AGE}s"
    else
        HB_AGE=-1
        HB_AGE_STR="never"
    fi

    # Last message from this instance
    LAST_MSG_AGE=-1
    LAST_MSG=""
    if [ -f "$COMM_FILE" ]; then
        LAST_LINE=$(grep "\"instance\":$N," "$COMM_FILE" | tail -1)
        if [ -n "$LAST_LINE" ]; then
            LAST_TS=$(echo "$LAST_LINE" | grep -oE '"ts":"[^"]+"' | head -1 | sed 's/"ts":"//; s/"$//')
            if [ -n "$LAST_TS" ]; then
                # Parse ISO-8601 to epoch
                LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_TS" +%s 2>/dev/null || echo 0)
                if [ "$LAST_EPOCH" -gt 0 ]; then
                    LAST_MSG_AGE=$((NOW - LAST_EPOCH))
                fi
            fi
            LAST_MSG=$(echo "$LAST_LINE" | grep -oE '"type":"[^"]+"' | sed 's/"type":"//; s/"$//')
        fi
    fi

    LAST_MSG_STR="${LAST_MSG_AGE}s"
    [ "$LAST_MSG_AGE" = "-1" ] && LAST_MSG_STR="never"

    # Determine state
    # fired if comm has fire notice with concurrence or [user] flag
    FIRED=""
    if [ -f "$COMM_FILE" ]; then
        FM=$(grep "\"type\":\"fire\",\"target\":$N" "$COMM_FILE" 2>/dev/null)
        if [ -n "$FM" ]; then
            if echo "$FM" | grep -q "\"concur\"" || echo "$FM" | grep -q "\[user\]"; then
                FIRED="yes"
            fi
        fi
    fi

    if [ -n "$FIRED" ]; then
        STATE="FIRED"
    elif [ "$HB_AGE" = "-1" ]; then
        STATE="UNKNOWN"
    elif [ "$HB_AGE" -lt 120 ]; then
        STATE="ALIVE"
    elif [ "$HB_AGE" -lt 1800 ]; then
        STATE="IDLE"
    else
        STATE="STALE"
    fi

    printf "%-5s %-10s %-15s %-15s %s\n" "$N" "$STATE" "$HB_AGE_STR" "$LAST_MSG_STR" "${LAST_MSG:-—}"

    # Show registered cwd + session_id from the instance record (v5+).
    REC="$WG_DIR/instances/${N}.json"
    if [ -f "$REC" ]; then
        REC_CWD=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("cwd",""))' "$REC" 2>/dev/null)
        REC_SID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("session_id",""))' "$REC" 2>/dev/null)
        REC_PID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pid",""))' "$REC" 2>/dev/null)
        printf "      cwd:        %s\n" "${REC_CWD:-<unknown>}"
        printf "      session_id: %s\n" "${REC_SID:-<none — direct query unavailable>}"
        printf "      pid:        %s\n" "${REC_PID:-<unknown>}"
    fi
done

echo ""
echo "=== Legend ==="
echo "  ALIVE   — heartbeat <2min ago"
echo "  IDLE    — heartbeat 2-30min ago"
echo "  STALE   — heartbeat >30min ago (candidate for firing)"
echo "  FIRED   — removed from team via fire notice"
echo "  UNKNOWN — no heartbeat file yet (may still be bootstrapping)"

# Pending signals
echo ""
echo "=== Pending wake-up signals ==="
SIG=$(ls "$WG_DIR/signals/" 2>/dev/null)
if [ -z "$SIG" ]; then
    echo "  (none)"
else
    for f in "$WG_DIR/signals/"wake-*.signal; do
        [ -e "$f" ] || continue
        target=$(basename "$f" | sed -E 's/^wake-([0-9]+)\.signal$/\1/')
        content=$(cat "$f" | head -c 200)
        echo "  → instance $target: $content"
    done
fi

# Active crons registered for this project (best-effort)
echo ""
echo "=== Comm log stats ==="
if [ -f "$COMM_FILE" ]; then
    TOTAL=$(wc -l < "$COMM_FILE" | tr -d ' ')
    SIZE=$(wc -c < "$COMM_FILE" | tr -d ' ')
    echo "  $TOTAL messages, $SIZE bytes"
    echo "  Last message: $(tail -1 "$COMM_FILE" | head -c 200)"
fi
