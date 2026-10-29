#!/bin/bash
# Move a card to a different column.
#
# Usage:   bash templates/cards-move.sh <card-ref> <target-column-name>
# Example: bash templates/cards-move.sh TH-100 Done
# Output:  updated card JSON

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

REF=${1:?card ref required, e.g. TH-100}
TARGET=${2:?target column name required}

PREFIX=${REF%%-*}
NUM=${REF##*-}

BID=$(curl -sf "${H[@]}" "$API/boards" \
  | jq -r --arg p "$PREFIX" '.[] | select((.prefix // "") | ascii_upcase == ($p | ascii_upcase)) | .id')
[ -n "$BID" ] || { echo "no board with prefix $PREFIX" >&2; exit 1; }

CARD=$(curl -sf "${H[@]}" "$API/boards/$BID/cards/number/$NUM")
CARD_ID=$(echo "$CARD" | jq -r .id)
[ -n "$CARD_ID" ] && [ "$CARD_ID" != "null" ] || { echo "no card $REF" >&2; exit 1; }

COL_ID=$(curl -sf "${H[@]}" "$API/boards/$BID/columns" \
  | jq -r --arg n "$TARGET" '.[] | select((.name // "") | ascii_downcase == ($n | ascii_downcase)) | .id' \
  | head -1)
[ -n "$COL_ID" ] || { echo "no column '$TARGET' on board $PREFIX" >&2; exit 1; }

curl -sf -X PUT "${H[@]}" \
  -d "$(jq -n --arg c "$COL_ID" '{column_id:$c}')" \
  "$API/boards/$BID/cards/$CARD_ID"
