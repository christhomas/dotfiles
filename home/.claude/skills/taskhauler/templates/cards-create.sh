#!/bin/bash
# Create a card.
#
# Usage:   bash templates/cards-create.sh <board-prefix-or-id> <column-name> <title> [description]
# Example: bash templates/cards-create.sh TH Backlog "Fix login bug" "Multi-line\ndescription"
# Output:  the created card JSON (includes the assigned .number)

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

REF=${1:?board prefix or id required}
COL_NAME=${2:?column name required (e.g. Backlog)}
TITLE=${3:?title required}
DESC=${4:-}

if [[ "$REF" =~ ^[0-9a-f]{8}- ]]; then
  BID=$REF
else
  BID=$(curl -sf "${H[@]}" "$API/boards" \
    | jq -r --arg p "$REF" '.[] | select((.prefix // "") | ascii_upcase == ($p | ascii_upcase)) | .id')
  [ -n "$BID" ] || { echo "no board with prefix $REF" >&2; exit 1; }
fi

CID=$(curl -sf "${H[@]}" "$API/boards/$BID/columns" \
  | jq -r --arg n "$COL_NAME" '.[] | select((.name // "") | ascii_downcase == ($n | ascii_downcase)) | .id' \
  | head -1)
[ -n "$CID" ] || { echo "no column '$COL_NAME' on board $REF" >&2; exit 1; }

curl -sf -X POST "${H[@]}" \
  -d "$(jq -n --arg c "$CID" --arg t "$TITLE" --arg d "$DESC" \
        '{column_id:$c, title:$t, description:$d, card_type:"task"}')" \
  "$API/boards/$BID/cards"
