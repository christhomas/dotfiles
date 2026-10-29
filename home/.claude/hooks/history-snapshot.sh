#!/usr/bin/env bash
# Snapshot every file Claude edits into <project-root>/.history/<same-path>.
#
# The anchor is the PROJECT ROOT, never the session's working directory.
# The Bash tool's cwd persists between calls, so a single `cd` used to move the
# anchor: snapshots landed in whatever directory the shell happened to be in,
# and - worse, because it was silent - a file outside that directory was skipped
# altogether. Anchoring on the root fixes both halves.
#
# Always exits 0. A snapshot failing must never block the edit that triggered it.

set -u

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_response.filePath // .tool_input.file_path // empty')
[ -n "$file" ] && [ -f "$file" ] || exit 0

# Project root, most reliable source first. CLAUDE_PROJECT_DIR is set by Claude
# Code for hooks. The git toplevel is derived from the edited FILE, so it is
# right regardless of where the shell is. .cwd is the last resort - and the one
# that caused the original bug.
root=${CLAUDE_PROJECT_DIR:-}
[ -n "$root" ] || root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root=$(printf '%s' "$payload" | jq -r '.cwd // empty')
[ -n "$root" ] || exit 0

# Edited outside this project: there is no tree to mirror it into.
case $file in
  "$root"/*) ;;
  *) exit 0 ;;
esac

rel=${file#"$root"/}

# Never snapshot the snapshots.
case $rel in
  .history/*|*/.history/*) exit 0 ;;
esac

base=${rel##*/}
case $base in
  *.*) stem=${base%.*}; ext=.${base##*.} ;;
  *)   stem=$base;      ext= ;;
esac

dest="$root/.history/$(dirname "$rel")"
mkdir -p "$dest" || exit 0
cp -p "$file" "$dest/${stem}_$(date +%Y%m%d%H%M%S)$ext" || exit 0
