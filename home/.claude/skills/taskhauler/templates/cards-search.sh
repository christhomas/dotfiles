#!/bin/bash
# Search cards on a board (server-side LIKE on title/description/labels).
#
# Usage:   bash templates/cards-search.sh <board-prefix-or-id> <query>
# Example: bash templates/cards-search.sh TH oauth

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

REF=${1:?board prefix or id required}
Q=${2:?search query required}

if [[ "$REF" =~ ^[0-9a-f]{8}- ]]; then
  BID=$REF
else
  BID=$(curl -sf "${H[@]}" "$API/boards" \
    | jq -r --arg p "$REF" '.[] | select((.prefix // "") | ascii_upcase == ($p | ascii_upcase)) | .id')
  [ -n "$BID" ] || { echo "no board with prefix $REF" >&2; exit 1; }
fi

# url-encode the query
QENC=$(jq -rn --arg q "$Q" '$q|@uri')

curl -sf "${H[@]}" "$API/boards/$BID/cards/search?q=$QENC" \
  | jq -r '.[] | [.number, .title, .status_name, .priority] | @tsv'
