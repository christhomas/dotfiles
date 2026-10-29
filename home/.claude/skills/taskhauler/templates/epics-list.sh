#!/bin/bash
# List epics for a board.
#
# Usage:   bash templates/epics-list.sh <board-prefix-or-id>

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

REF=${1:?board prefix or id required}

if [[ "$REF" =~ ^[0-9a-f]{8}- ]]; then
  BID=$REF
else
  BID=$(curl -sf "${H[@]}" "$API/boards" \
    | jq -r --arg p "$REF" '.[] | select((.prefix // "") | ascii_upcase == ($p | ascii_upcase)) | .id')
  [ -n "$BID" ] || { echo "no board with prefix $REF" >&2; exit 1; }
fi

curl -sf "${H[@]}" "$API/boards/$BID/epics" \
  | jq -r 'sort_by(.position)[] | [.position, .name, .color, .id] | @tsv'
