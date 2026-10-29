#!/bin/bash
# Build a shareable card URL from a ref.
#
# Usage:   bash templates/url-build.sh <PREFIX-NUMBER>
# Example: bash templates/url-build.sh TH-100
#          → http://taskhauler.localhost/TH/100

set -e
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/_preamble.sh"

REF=${1:?card ref required, e.g. TH-100}
PREFIX=${REF%%-*}
NUM=${REF##*-}

echo "$URL/$PREFIX/$NUM"
