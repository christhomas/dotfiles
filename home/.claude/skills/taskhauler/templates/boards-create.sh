#!/bin/bash
# Create a board. Backend derives the prefix from the name unless one is given.
#
# Usage:   bash templates/boards-create.sh <name> [prefix] [description]
# Example: bash templates/boards-create.sh "Mobile Bugs"
# Example: bash templates/boards-create.sh "Mobile Bugs" MOB "iOS + Android bug tracking"

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

NAME=${1:?board name required}
PREFIX=${2:-}
DESC=${3:-}

BODY=$(jq -n \
  --arg n "$NAME" --arg p "$PREFIX" --arg d "$DESC" \
  '{name:$n} + (if $p == "" then {} else {prefix:$p} end)
              + (if $d == "" then {} else {description:$d} end)')

curl -sf -X POST "${H[@]}" -d "$BODY" "$API/boards"
