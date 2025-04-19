#!/bin/bash

set -euo pipefail

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# === 1. Install Homebrew if missing ===
if ! command -v brew >/dev/null 2>&1; then
  info "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add brew to PATH (macOS or Linux)
  if [[ "$(uname -s)" == "Darwin" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
else
  info "Homebrew is already installed."
fi

# === 2. Install packages from Brewfile ===
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && dirname $(pwd))"
BREWFILE="$REPO_DIR/home/.Brewfile"

if [[ -f "$BREWFILE" ]]; then
  info "Installing packages from ${BREWFILE}..."
  brew bundle --file="$BREWFILE"
else
  error "No .Brewfile found at $BREWFILE"
  exit 1
fi

# === 3. Run some custom commands because otherwise somethings won't run smoothly
OMP_BIN="$(which oh-my-posh)"

if xattr -p com.apple.quarantine "${OMP_BIN}" &>/dev/null; then
  echo "[INFO] Removing quarantine from oh-my-posh..."
  xattr -d com.apple.quarantine "${OMP_BIN}"
else
  echo "[INFO] oh-my-posh is already unquarantined."
fi

info "Bootstrap complete! 🎉"
