#!/bin/bash
# claude-workgroup bootstrap — handles `create` and `instance` subcommands.
#
# Usage:
#   bootstrap.sh create <workgroup>
#     Initialise a new workgroup directory at ~/.claude/workgroups/<workgroup>/.
#     Idempotent — safe to re-run.
#
#   bootstrap.sh selfid
#     Print a unique self-identification nonce. Step 1 of the reliable
#     two-step join (see below). Must be run in its OWN tool call so the
#     nonce gets flushed to this session's transcript before step 2.
#
#   bootstrap.sh instance <N> <workgroup> [--self-nonce <n> | --session-id <uuid>] [--force]
#     Register THIS Claude as instance <N> in the named workgroup, writing
#     ~/.claude/workgroups/<workgroup>/instances/<N>.json:
#
#       { "instance": N, "cwd": "...", "session_id": "...",
#         "pid": <PPID>, "joined_at": "<ISO-8601 UTC>" }
#
#     The session_id is the UUID `claude -p --resume` needs. The HUMAN
#     never types it — the AGENT discovers its own. How session_id is
#     resolved, most reliable first:
#
#       --session-id <uuid>   explicit (e.g. the session was launched with
#                             `claude --session-id <uuid>`).
#       --self-nonce <nonce>  RELIABLE self-discovery: grep transcripts for
#                             a nonce this session printed via `selfid`,
#                             and take the .jsonl that contains it. Works
#                             even with many sessions in one cwd.
#       (neither)             Last-resort "newest .jsonl" guess — allowed
#                             ONLY when a single session is active in the
#                             cwd. Refuses if 2+ are (that guess mis-binds
#                             the wrong UUID — the bug this guard prevents).
#
#     RELIABLE TWO-STEP JOIN (what the SKILL instructs the agent to do):
#       1) NONCE=$(bootstrap.sh selfid)         # in one tool call
#       2) bootstrap.sh instance N wg --self-nonce "$NONCE"   # a LATER call
#
#     Other instances query this Claude via:
#       (cd <cwd> && claude -p --resume <session_id> "...")   # idle targets only
#
#     Errors if instance N is already bound to a DIFFERENT session unless
#     --force.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

SUBCMD="${1:?Usage: bootstrap.sh create WORKGROUP, or bootstrap.sh instance N WORKGROUP}"
shift

case "$SUBCMD" in
    create)
        WORKGROUP="${1:?Usage: bootstrap.sh create <workgroup>}"
        wg_ensure_dirs "$WORKGROUP"
        echo "workgroup '$WORKGROUP' initialised at $(wg_root "$WORKGROUP")"
        ;;
    selfid)
        # Step 1 of reliable self-identification: print a unique nonce.
        # The agent must run this in its OWN tool call, then on a LATER
        # tool call run `instance ... --self-nonce <nonce>`. By then the
        # nonce is flushed into THIS session's transcript, so
        # wg_discover_session_id can pinpoint the right .jsonl even with
        # several sessions sharing the cwd.
        wg_gen_nonce
        echo
        ;;
    instance)
        INSTANCE="${1:?Usage: bootstrap.sh instance <N> <workgroup> [flags]}"
        WORKGROUP="${2:?Usage: bootstrap.sh instance <N> <workgroup> [flags]}"
        shift 2
        FORCE=0
        SELF_NONCE=""
        EXPLICIT_SID=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --force)       FORCE=1; shift ;;
                --self-nonce)  SELF_NONCE="${2:?--self-nonce needs a value}"; shift 2 ;;
                --session-id)  EXPLICIT_SID="${2:?--session-id needs a value}"; shift 2 ;;
                *) echo "bootstrap: unknown flag '$1'" >&2; exit 2 ;;
            esac
        done

        wg_ensure_dirs "$WORKGROUP"
        WG_DIR="$(wg_root "$WORKGROUP")"
        REC_FILE="$WG_DIR/instances/${INSTANCE}.json"

        cwd="$(pwd -P)"
        pid="$(wg_my_pid)"
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

        # --- resolve session id (most reliable source first) -------------
        sid=""
        sid_method=""
        if [[ -n "$EXPLICIT_SID" ]]; then
            sid="$EXPLICIT_SID"
            sid_method="explicit --session-id"
        elif [[ -n "$SELF_NONCE" ]]; then
            sid="$(wg_discover_session_id "$SELF_NONCE")"
            sid_method="nonce self-discovery"
            if [[ -z "$sid" ]]; then
                echo "error: nonce '$SELF_NONCE' not found in any transcript yet." >&2
                echo "       Run 'bootstrap.sh selfid' in a SEPARATE earlier tool call and" >&2
                echo "       pass the printed nonce here — it must be flushed to the transcript" >&2
                echo "       first (don't emit the nonce and join in the same tool call)." >&2
                exit 3
            fi
        else
            # No reliable source. Only fall back to the guess if it's
            # UNAMBIGUOUS (exactly one recent session in this cwd).
            recent="$(wg_recent_session_count 120)"
            if (( recent > 1 )); then
                echo "error: $recent concurrent sessions share this cwd — the 'newest .jsonl'" >&2
                echo "       guess is UNSAFE (mis-binds the instance to the wrong UUID, the" >&2
                echo "       exact bug this guard exists to prevent). Use the two-step join:" >&2
                echo "         1) bootstrap.sh selfid                                    # prints NONCE" >&2
                echo "         2) bootstrap.sh instance $INSTANCE $WORKGROUP --self-nonce <NONCE>" >&2
                exit 4
            fi
            sid="$(wg_session_id)"
            sid_method="newest-.jsonl guess (single session in cwd)"
        fi

        if [[ -z "$sid" ]]; then
            echo "warning: could not resolve session_id; 'claude -p --resume' won't work for this instance." >&2
        fi

        # Refuse to clobber a DIFFERENT live session unless --force.
        if [[ -f "$REC_FILE" && "$FORCE" -eq 0 ]]; then
            existing_sid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("session_id",""))' "$REC_FILE" 2>/dev/null || echo "")"
            if [[ -n "$existing_sid" && -n "$sid" && "$existing_sid" != "$sid" ]]; then
                echo "error: instance $INSTANCE is already registered to session $existing_sid" >&2
                echo "       (resolved current session is $sid). Pass --force to take the slot," >&2
                echo "       or pick a different instance number." >&2
                exit 2
            fi
        fi

        python3 - "$REC_FILE" "$INSTANCE" "$cwd" "$sid" "$pid" "$ts" <<'PY'
import json, sys
path, n, cwd, sid, pid, ts = sys.argv[1:]
rec = {
    "instance":   int(n),
    "cwd":        cwd,
    "session_id": sid,
    "pid":        int(pid),
    "joined_at":  ts,
}
with open(path, "w") as f:
    json.dump(rec, f, indent=2)
    f.write("\n")
PY

        echo "instance $INSTANCE registered in workgroup '$WORKGROUP'"
        echo "  cwd:        $cwd"
        echo "  session_id: ${sid:-<unknown>}  (via $sid_method)"
        echo "  pid:        $pid"
        echo "  record:     $REC_FILE"
        ;;
    *)
        echo "Usage: bootstrap.sh {create <wg> | selfid | instance <N> <wg> [--self-nonce <n> | --session-id <uuid>] [--force]}" >&2
        exit 2
        ;;
esac