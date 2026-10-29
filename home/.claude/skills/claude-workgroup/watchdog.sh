#!/bin/bash
# Background watchdog: runs cron-tick.sh every N seconds and only triggers
# a signal file if ACTION_NEEDED: yes. This replaces the token-burning
# CronCreate approach — the watchdog runs in bash, not Claude, so heartbeat
# ticks cost nothing.
#
# Usage: watchdog.sh <workgroup> <instance> [interval-seconds]
#
# Run in background via Claude's Bash tool with run_in_background: true.

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WORKGROUP="${1:?Usage: watchdog.sh <workgroup> <instance> [interval]}"
INSTANCE="${2:?Usage: watchdog.sh <workgroup> <instance> [interval]}"
INTERVAL="${3:-60}"  # default 60s — heartbeat cost is zero, so this can be fast

WG_DIR="$(wg_root "$WORKGROUP")"
wg_ensure_dirs "$WORKGROUP"
TICK_SCRIPT="$HOME/.claude/skills/claude-workgroup/cron-tick.sh"
SIGNAL_FILE="$WG_DIR/signals/wake-${INSTANCE}.signal"
PIDFILE="$WG_DIR/watchdog-${INSTANCE}.pid"

# Kill any previous watchdog for this instance
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE")
    kill "$OLD_PID" 2>/dev/null
fi
echo $$ > "$PIDFILE"

# Cleanup on exit
cleanup() { rm -f "$PIDFILE"; exit 0; }
trap cleanup INT TERM EXIT

echo "watchdog for workgroup=$WORKGROUP instance=$INSTANCE started (pid=$$, interval=${INTERVAL}s)"

while true; do
    # Run tick silently; only act if ACTION_NEEDED: yes
    OUTPUT=$(bash "$TICK_SCRIPT" "$WORKGROUP" "$INSTANCE" 2>/dev/null)

    if echo "$OUTPUT" | grep -q "ACTION_NEEDED: yes"; then
        # Only write a signal if one isn't already there (avoid stomping richer signal from a peer)
        if [ ! -f "$SIGNAL_FILE" ]; then
            cat > "$SIGNAL_FILE" << EOF
{"from":"watchdog","ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","msg":"watchdog detected ACTION_NEEDED. Run: bash ~/.claude/skills/claude-workgroup/cron-tick.sh $WORKGROUP $INSTANCE — then respond to any directed messages or signals."}
EOF
        fi
    fi

    sleep "$INTERVAL"
done
