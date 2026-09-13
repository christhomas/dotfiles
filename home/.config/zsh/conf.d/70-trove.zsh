# trove: daily secrets. Unlock once, then `git@github-trove:…` SSH remotes and
# `git commit -S` GPG signing both route through the unlocked agent.
export TROVE_VAULT="${XDG_DATA_HOME:-$HOME/.local/share}/trove/vault.kdbx"

tunlock() {
  eval "$(command trove unlock "${1:-$TROVE_VAULT}" --export)" || return
  ln -sf "$(command trove gpg-agent socket)" "$HOME/.trove-gnupg/S.gpg-agent" 2>/dev/null
  echo "trove: unlocked — 'git@github-trove:…' SSH + 'git commit -S' now route through trove"
}

alias tlock='command trove lock'
alias tstatus='command trove status'
