#!/bin/bash
# List cards on a board.
#
# Usage:   bash templates/cards-list.sh <board-prefix-or-id>
# Example: bash templates/cards-list.sh TH
# Output:  number  title  status  priority  assignee   (tab-separated)

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

REF=${1:?board prefix or id required}

# Resolve prefix → board id (if it's not already a UUID-looking id)
if [[ "$REF" =~ ^[0-9a-f]{8}- ]]; then
  BID=$REF
else
  BID=$(curl -sf "${H[@]}" "$API/boards" \
    | jq -r --arg p "$REF" '.[] | select((.prefix // "") | ascii_upcase == ($p | ascii_upcase)) | .id')
  [ -n "$BID" ] || { echo "no board with prefix $REF" >&2; exit 1; }
fi

curl -sf "${H[@]}" "$API/boards/$BID/cards" \
  | jq -r '.[] | [.number, .title, .status_name, .priority, .assignee_name] | @tsv'
