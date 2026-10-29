#!/bin/bash
# List service accounts (admin only).
#
# Usage:   bash templates/service-accounts-list.sh
# Output:  id  name  display_name  is_admin   (tab-separated)

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

curl -sf "${H[@]}" "$API/service-accounts" \
  | jq -r '.[] | [.id, .email // .name, .display_name, .is_admin] | @tsv'
