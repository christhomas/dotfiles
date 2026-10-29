#!/bin/bash
# message-instance.sh -- snapshot pull from an IDLE workgroup member.
#
# Looks up the target instance's session record (cwd + session_id + pid)
# and spawns `claude -p --resume <sid>` from their cwd to ask a one-shot
# question, returning the reply on stdout.
#
# ============================ DANGER ============================
# `claude -p --resume <sid>` does NOT attach to a running session. It
# spawns a SEPARATE headless Claude that replays <sid>'s history and
# runs with FULL TOOL ACCESS in the target's working directory. If the
# target session is LIVE (actively being worked in), you now have TWO
# Claudes editing the same repo concurrently — the classic lost-update /
# ghost-edit race that corrupts the working tree.
#
# Worse: if the session-id resolution is ambiguous (two sessions share a
# cwd, so the "newest .jsonl" heuristic in wg_session_id picks the wrong
# one), you can end up resuming YOUR OWN session — spawning a twin of
# yourself that mutates the repo behind your back.
#
# THEREFORE this script REFUSES to resume a target that looks live:
#   * its heartbeat file was touched within $LIVE_THRESHOLD seconds, OR
#   * its recorded pid is still alive (kill -0), OR
#   * its recorded pid == our own ($PPID)  → that's us; never resume self.
#
# A live target is exactly the case where you must NOT use this. Use
# post-comm.sh (+ wake-instance.sh) instead: that injects into the
# target's running conversation through the comm channel + hooks, with
# no second mutating process. `--resume` is only safe against an IDLE or
# dead session (e.g. pulling context from a finished run).
# ================================================================
#
# Usage:
#   message-instance.sh <workgroup> <target-instance> "<question>" [flags]
#
# Flags:
#   --force-live   Override the liveness refusal (you accept the
#                  concurrent-mutation risk). Still cannot resume self.
#   --rw           Allow the resumed twin to mutate files. Default is
#                  READ-ONLY (Edit/Write/NotebookEdit disabled) so a
#                  status pull can never silently change the repo.
#
# Output: the target Claude's reply on stdout. Exit 0 = answered.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Seconds since a heartbeat touch within which a target is treated LIVE.
# Watchdog/hooks touch heartbeats roughly every 60s, so 180s = ~3 missed
# beats = confidently idle/dead.
LIVE_THRESHOLD="${WG_LIVE_THRESHOLD:-180}"

WORKGROUP="${1:?Usage: message-instance.sh <workgroup> <target> \"<question>\" [--force-live] [--rw]}"
TARGET="${2:?Usage: message-instance.sh <workgroup> <target> \"<question>\" [--force-live] [--rw]}"
QUESTION="${3:?Usage: message-instance.sh <workgroup> <target> \"<question>\" [--force-live] [--rw]}"
shift 3

FORCE_LIVE=0
ALLOW_WRITE=0
for arg in "$@"; do
    case "$arg" in
        --force-live) FORCE_LIVE=1 ;;
        --rw)         ALLOW_WRITE=1 ;;
        *) echo "message-instance: unknown flag '$arg'" >&2; exit 2 ;;
    esac
done

REC_FILE="$(wg_root "$WORKGROUP")/instances/${TARGET}.json"
if [[ ! -f "$REC_FILE" ]]; then
    echo "message-instance: no instance $TARGET in workgroup '$WORKGROUP'" >&2
    echo "  (expected $REC_FILE)" >&2
    exit 2
fi

read -r cwd sid pid < <(python3 -c '
import json, sys
r = json.load(open(sys.argv[1]))
print(r.get("cwd",""), r.get("session_id",""), r.get("pid",0))
' "$REC_FILE")

if [[ -z "$sid" ]]; then
    echo "message-instance: instance $TARGET has no session_id recorded" >&2
    echo "  (record at $REC_FILE — was it bootstrapped without a session?)" >&2
    exit 2
fi

# --- Guard 1: never resume our own session ------------------------------
# $PPID inside a Bash tool call is the Claude binary that invoked us. If
# the target's recorded pid matches, we'd be resuming ourselves.
MY_PID="$(wg_my_pid)"
if [[ -n "$pid" && "$pid" != "0" && "$pid" == "$MY_PID" ]]; then
    echo "message-instance: REFUSING — instance $TARGET's pid ($pid) is THIS process." >&2
    echo "  Resuming your own session spawns a twin of yourself that edits the repo" >&2
    echo "  concurrently. This is never what you want. Use post-comm.sh to talk to" >&2
    echo "  other instances; you don't need to message yourself." >&2
    exit 3
fi

# --- Guard 2: refuse to resume a LIVE target ----------------------------
is_live=0
live_reason=""

# 2a. heartbeat freshness
HEARTBEAT="$(wg_root "$WORKGROUP")/heartbeats/instance-${TARGET}"
if [[ -f "$HEARTBEAT" ]]; then
    now="$(date +%s)"
    # macOS stat -f %m ; GNU stat -c %Y. Try both.
    mtime="$(stat -f %m "$HEARTBEAT" 2>/dev/null || stat -c %Y "$HEARTBEAT" 2>/dev/null || echo 0)"
    age=$(( now - mtime ))
    if (( age >= 0 && age < LIVE_THRESHOLD )); then
        is_live=1
        live_reason="heartbeat touched ${age}s ago (< ${LIVE_THRESHOLD}s)"
    fi
fi

# 2b. pid liveness
if [[ "$is_live" -eq 0 && -n "$pid" && "$pid" != "0" ]] && kill -0 "$pid" 2>/dev/null; then
    is_live=1
    live_reason="recorded pid $pid is still alive"
fi

if [[ "$is_live" -eq 1 && "$FORCE_LIVE" -eq 0 ]]; then
    echo "message-instance: REFUSING — instance $TARGET looks LIVE ($live_reason)." >&2
    echo "" >&2
    echo "  Resuming a live session spawns a SECOND headless Claude that edits the" >&2
    echo "  same working directory concurrently — a lost-update / ghost-edit race." >&2
    echo "" >&2
    echo "  To coordinate with a live instance, use the comm channel instead:" >&2
    echo "    post-comm.sh $WORKGROUP <me> <type> \"<msg>\" to=$TARGET" >&2
    echo "    wake-instance.sh $WORKGROUP $TARGET \"<nudge>\"" >&2
    echo "" >&2
    echo "  Only use --resume against an IDLE/finished session. If you are CERTAIN" >&2
    echo "  the target is idle and accept the risk, re-run with --force-live." >&2
    exit 4
fi

# --- Dispatch -----------------------------------------------------------
# claude -p --resume is cwd-scoped: the session file lives under
# ~/.claude/projects/<encoded-cwd>/, so cd there first. Subshell so the
# cd doesn't leak. Default to READ-ONLY (no file mutation) so a status
# pull can never silently change the repo; --rw opts into full tools.
if [[ "$ALLOW_WRITE" -eq 1 ]]; then
    ( cd "$cwd" && claude -p --resume "$sid" "$QUESTION" )
else
    ( cd "$cwd" && claude -p --resume "$sid" \
        --disallowedTools "Edit" "Write" "NotebookEdit" \
        "$QUESTION" )
fi