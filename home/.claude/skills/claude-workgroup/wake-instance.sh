#!/bin/bash
# Wake up a specific workgroup instance by writing a signal file.
# The target instance's check-comm.sh hook will detect it on next tool call.
#
# Usage: wake-instance.sh <workgroup> <target-instance> <sender-instance> <message>

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WORKGROUP="${1:?Usage: wake-instance.sh <workgroup> <target> <sender> <message>}"
TARGET="${2:?Usage: wake-instance.sh <workgroup> <target> <sender> <message>}"
SENDER="${3:?Usage: wake-instance.sh <workgroup> <target> <sender> <message>}"
shift 3
MESSAGE="$*"

wg_ensure_dirs "$WORKGROUP"
SIGNAL_FILE="$(wg_root "$WORKGROUP")/signals/wake-${TARGET}.signal"

cat > "$SIGNAL_FILE" << EOF
{"from":${SENDER},"ts":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","msg":"${MESSAGE}"}
EOF

echo "Signal sent to instance ${TARGET} at ${SIGNAL_FILE}"
