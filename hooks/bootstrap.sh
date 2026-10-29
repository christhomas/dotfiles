#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Reusable functions
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }
banner_start() { echo -e "\033[1;34m========== $* ==========\033[0m"; }
banner_ok() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
banner_skip() { echo -e "\033[1;34m[SKIP]\033[0m $*"; }
banner_fail() { echo -e "\033[1;31m[FAILED]\033[0m $*" >&2; }

# All the bootstrap scripts, broken into individual files
source "$SCRIPT_DIR/bootstrap/install-brew"
source "$SCRIPT_DIR/bootstrap/install-brewfile"
source "$SCRIPT_DIR/bootstrap/install-oh-my-posh"
source "$SCRIPT_DIR/bootstrap/install-open-in-nvim"
source "$SCRIPT_DIR/bootstrap/install-keyboard"
source "$SCRIPT_DIR/bootstrap/install-claude"


info "Bootstrap complete! 🎉"
