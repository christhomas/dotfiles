#!/bin/bash
# Add a comment to a card and verify it landed byte-equal.
# Multi-line safe — body is read from stdin (preserves newlines, backticks, $vars).
#
# Usage:   echo "your body" | bash templates/comments-add.sh <card-ref>
#          bash templates/comments-add.sh <card-ref> < body.txt
# Example: cat findings.md | bash templates/comments-add.sh TH-100

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

REF=${1:?card ref required, e.g. TH-100}

BODY=$(cat)
[ -n "$BODY" ] || { echo "comment body required on stdin" >&2; exit 1; }

PREFIX=${REF%%-*}
NUM=${REF##*-}

BID=$(curl -sf "${H[@]}" "$API/boards" \
  | jq -r --arg p "$PREFIX" '.[] | select((.prefix // "") | ascii_upcase == ($p | ascii_upcase)) | .id')
[ -n "$BID" ] || { echo "no board with prefix $PREFIX" >&2; exit 1; }

CARD_ID=$(curl -sf "${H[@]}" "$API/boards/$BID/cards/number/$NUM" | jq -r .id)
[ -n "$CARD_ID" ] && [ "$CARD_ID" != "null" ] || { echo "no card $REF" >&2; exit 1; }

POSTED=$(curl -sf -X POST "${H[@]}" \
  -d "$(jq -n --arg b "$BODY" '{body:$b}')" \
  "$API/cards/$CARD_ID/comments")
PID=$(echo "$POSTED" | jq -r .id)

# read-back verify
ACTUAL=$(curl -sf "${H[@]}" "$API/cards/$CARD_ID/comments" \
  | jq -r --arg id "$PID" '.[] | select(.id == $id) | .body')

if [ "$ACTUAL" = "$BODY" ]; then
  echo "OK posted ${PID:0:8} on $REF"
else
  echo "MISMATCH on $REF — posted body != read-back body" >&2
  exit 1
fi
