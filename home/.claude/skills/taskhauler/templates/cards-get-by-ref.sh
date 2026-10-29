#!/bin/bash
# Fetch a single card by ref (e.g. TH-100).
#
# Usage:   bash templates/cards-get-by-ref.sh <PREFIX-NUMBER>
# Example: bash templates/cards-get-by-ref.sh TH-100
# Output:  full card JSON

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

REF=${1:?card ref required, e.g. TH-100}
PREFIX=${REF%%-*}
NUM=${REF##*-}
NUM=${NUM##TH-}  # tolerate accidental double prefix

BID=$(curl -sf "${H[@]}" "$API/boards" \
  | jq -r --arg p "$PREFIX" '.[] | select((.prefix // "") | ascii_upcase == ($p | ascii_upcase)) | .id')
[ -n "$BID" ] || { echo "no board with prefix $PREFIX" >&2; exit 1; }

curl -sf "${H[@]}" "$API/boards/$BID/cards/number/$NUM"
