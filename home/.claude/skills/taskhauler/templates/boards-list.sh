#!/bin/bash
# List boards with prefix, name, and card count per board.
#
# Usage:   bash templates/boards-list.sh
# Output:  prefix  name  count   (tab-separated, then a markdown table)

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

BOARDS=$(curl -sf "${H[@]}" "$API/boards")

ROWS=()
while IFS=$'\t' read -r id prefix name; do
  count=$(curl -sf "${H[@]}" "$API/boards/$id/cards" | jq 'length')
  ROWS+=("$prefix	$name	$count")
done < <(echo "$BOARDS" | jq -r '.[] | [.id, .prefix, .name] | @tsv')

printf '%s\n' "${ROWS[@]}"
echo
echo "| Prefix | Name | Cards |"
echo "|---|---|---|"
for row in "${ROWS[@]}"; do
  IFS=$'\t' read -r p n c <<< "$row"
  printf '| %s | %s | %s |\n' "$p" "$n" "$c"
done
