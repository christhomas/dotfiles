# $ZDOTDIR/.zprofile — login shells. Environment + PATH only.
# Safe for non-interactive use: no output, no prompts, no interactive-only setup.

# Git: don't take the index lock for read-only operations (status, rev-parse).
# Avoids index corruption when prompts/editors/AI agents poll git concurrently.
export GIT_OPTIONAL_LOCKS=0

export EDITOR="${EDITOR:-nvim}"
export VISUAL="$EDITOR"

export GOPATH="$HOME/go"
export PNPM_HOME="$HOME/Library/pnpm"

# ── PATH ─────────────────────────────────────────────────
# path is tied to PATH; -U keeps it deduplicated (first occurrence wins).
typeset -U path PATH

path=(
  "$HOME/.local/bin"                          # personal scripts
  "$HOME/go/bin"                              # Go
  "$PNPM_HOME"                                # pnpm
  "$HOME/.bun/bin"                            # bun
  "$HOME/.opencode/bin"                       # opencode
  "$HOME/.codeium/windsurf/bin"               # Windsurf
  /opt/homebrew/opt/python@3.11/libexec/bin   # Homebrew Python 3.11 (unversioned names)
  /opt/homebrew/bin                           # Homebrew (Apple Silicon)
  /usr/local/bin                              # Homebrew (Intel fallback)
  $path
)

# Drop any entry that doesn't exist, and any empty entry (an empty PATH
# element means "current directory" — never wanted).
path=(${^path}(N-/))

# Rust / cargo — appends to PATH itself, so run after the block above.
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# ── Per-machine overrides (not tracked by dotman) ────────
[ -f "$ZDOTDIR/.zprofile.local" ] && . "$ZDOTDIR/.zprofile.local"
