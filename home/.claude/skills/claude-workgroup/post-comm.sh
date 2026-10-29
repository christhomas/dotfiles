#!/bin/bash
# Append a single JSON message to a workgroup's comm.jsonl log.
# Bootstrap adds "Bash(bash ~/.claude/skills/claude-workgroup/post-comm.sh *)"
# to settings.local.json so instances can post without a permission prompt.
#
# Usage:
#   post-comm.sh <workgroup> <instance> <type> <msg> [to=<target|all>] [re=<subject>]
#
# `<workgroup>` is the workgroup name; resolves to ~/.claude/workgroups/<workgroup>/.
# Workgroup state is user-level (not per-project) so multiple projects /
# Claude instances on the same machine can coordinate via one named
# workgroup independent of where each Claude is running from.
#
# Required JSON fields produced: instance, type, ts (ISO-8601 UTC), msg
# Optional fields: to, re, target, reason, concur (pass as key=value after msg)

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

WORKGROUP="${1:?workgroup name required}"
INSTANCE="${2:?instance required}"
TYPE="${3:?type required}"
MSG="${4:?msg required}"
shift 4

wg_ensure_dirs "$WORKGROUP"
COMM="$(wg_root "$WORKGROUP")/comm.jsonl"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# JSON-escape a string for safe embedding: backslash, double-quote, control chars.
json_escape() {
  python3 -c 'import sys,json; print(json.dumps(sys.argv[1]))' "$1"
}

# Base JSON. Use python for correctness since msg content may contain quotes/newlines.
python3 - "$INSTANCE" "$TYPE" "$TS" "$MSG" "$@" <<'PY' >> "$COMM"
import json, sys
instance = int(sys.argv[1])
msg_type = sys.argv[2]
ts       = sys.argv[3]
msg      = sys.argv[4]
extras   = sys.argv[5:]

obj = {"instance": instance, "type": msg_type, "ts": ts, "msg": msg}
for kv in extras:
    if "=" in kv:
        k, v = kv.split("=", 1)
        # Try numeric; fall back to string. "to" can be list-like "1,2".
        if "," in v and all(p.strip().isdigit() for p in v.split(",")):
            obj[k] = [int(p) for p in v.split(",")]
        elif v.isdigit() or (v.startswith("-") and v[1:].isdigit()):
            obj[k] = int(v)
        else:
            obj[k] = v
print(json.dumps(obj))
PY
