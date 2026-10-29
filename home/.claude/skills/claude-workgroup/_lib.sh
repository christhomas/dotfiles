#!/bin/bash
# claude-workgroup helpers shared across scripts.
#
# Sourced by post-comm.sh, check-comm.sh, bootstrap.sh, etc. Defines:
#   wg_root <name>             — echoes $HOME/.claude/workgroups/<name>
#   wg_ensure_dirs <name>      — mkdir's the standard subdir tree
#   wg_session_id              — best-effort discovery of the calling Claude's session id
#                                (newest .jsonl in ~/.claude/projects/<encoded-cwd>/)
#   wg_encode_cwd <abs-path>   — claude's cwd-encoding scheme (/foo/bar -> -foo-bar)
#   wg_my_pid                  — Claude Code process pid (== $PPID inside a hook/script)
#
# Layout produced by wg_ensure_dirs:
#   ~/.claude/workgroups/<name>/
#     comm.jsonl                — append-only message log (Slack channel)
#     instances/<N>.json        — per-instance identity (session_id + cwd + pid + joined_at)
#     offsets/instance-<N>.offset — per-instance read cursor into comm.jsonl
#     signals/wake-<N>.signal   — inbound wake-up signal files (deleted on receipt)
#     heartbeats/instance-<N>   — touched by hooks/watchdog as liveness proof

set -uo pipefail

wg_root() {
    local name="${1:?workgroup name required}"
    printf '%s/.claude/workgroups/%s' "$HOME" "$name"
}

wg_ensure_dirs() {
    local name="${1:?workgroup name required}"
    local root
    root="$(wg_root "$name")"
    mkdir -p "$root/instances" "$root/offsets" "$root/signals" "$root/heartbeats"
    [ -f "$root/comm.jsonl" ] || : > "$root/comm.jsonl"
}

# Encode an absolute path the way Claude does for ~/.claude/projects/:
# replace every '/' with '-'. (e.g. /Volumes/foo/bar -> -Volumes-foo-bar)
wg_encode_cwd() {
    local abs="${1:?abs path required}"
    printf '%s' "$abs" | tr '/' '-'
}

# UNRELIABLE — kept only as a last-resort fallback. Picks the newest
# .jsonl in ~/.claude/projects/<encoded-cwd>/. This GUESS loses when two
# Claude sessions share a cwd (it can return the OTHER session's id),
# which silently mis-binds an instance to the wrong UUID. Prefer
# wg_discover_session_id (nonce-based, concurrency-proof) for joins.
wg_session_id() {
    local cwd encoded dir newest
    cwd="$(pwd -P)"
    encoded="$(wg_encode_cwd "$cwd")"
    dir="$HOME/.claude/projects/$encoded"
    [ -d "$dir" ] || { echo ""; return; }
    newest="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)"
    [ -z "$newest" ] && { echo ""; return; }
    basename "$newest" .jsonl
}

# How many .jsonl in the cwd's project dir were modified in the last
# $1 seconds (default 120). >1 means concurrent sessions share this cwd,
# so wg_session_id's "newest" guess is unsafe — callers should require
# the nonce path instead. Echoes the count.
wg_recent_session_count() {
    local window="${1:-120}" cwd encoded dir now n
    cwd="$(pwd -P)"
    encoded="$(wg_encode_cwd "$cwd")"
    dir="$HOME/.claude/projects/$encoded"
    [ -d "$dir" ] || { echo 0; return; }
    now="$(date +%s)"
    n=0
    for f in "$dir"/*.jsonl; do
        [ -f "$f" ] || continue
        local m age
        m="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
        age=$(( now - m ))
        if (( age >= 0 && age < window )); then n=$(( n + 1 )); fi
    done
    echo "$n"
}

# Generate a unique self-identification nonce. The calling session prints
# this (in one tool call) so that, on a SUBSEQUENT call,
# wg_discover_session_id can find which transcript .jsonl is "ours".
wg_gen_nonce() {
    printf 'WG-SELFID-%s-%s-%s%s' \
        "$(date +%s 2>/dev/null || echo 0)" "${PPID:-0}" "${RANDOM:-0}" "${RANDOM:-0}"
}

# RELIABLE session-id discovery. Given a nonce the calling session ALREADY
# emitted in a prior, completed tool call (so it's flushed to that
# session's transcript), find which .jsonl under the cwd's project dir
# contains it. That file IS this session; its basename is the session id.
# Concurrency-proof: the nonce is unique to the session that printed it.
# Retries briefly to absorb transcript-flush lag. Echoes "" if not found.
wg_discover_session_id() {
    local nonce="${1:?nonce required}"
    local cwd encoded dir
    cwd="$(pwd -P)"
    encoded="$(wg_encode_cwd "$cwd")"
    dir="$HOME/.claude/projects/$encoded"
    [ -d "$dir" ] || { echo ""; return; }
    local attempt match
    for attempt in 1 2 3 4 5; do
        # Most-recently-modified match wins so a stale older hit can never
        # outvote the live session's transcript.
        match="$(grep -lF "$nonce" "$dir"/*.jsonl 2>/dev/null | while read -r f; do
                    printf '%s\t%s\n' \
                        "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)" "$f"
                 done | sort -rn | head -1 | cut -f2-)"
        if [ -n "$match" ]; then
            basename "$match" .jsonl
            return
        fi
        sleep 1
    done
    echo ""
}

# The Claude Code process pid. From inside a Bash tool call (which is
# what every script here is invoked as), $PPID points at the Claude
# binary. From a backgrounded watchdog spawned via run_in_background,
# the chain is the same.
wg_my_pid() {
    printf '%s' "${PPID:-0}"
}