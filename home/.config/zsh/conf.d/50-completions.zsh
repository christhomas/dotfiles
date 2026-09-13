# Completion function directories must go on fpath BEFORE compinit runs.
# Prepend, so these win over zsh's bundled functions on a name clash.
# (Notably: zsh ships _openstack, which claims the `trove` command name and
#  then fails with `_values:compvalues`. Trove's own _trove must come first.)
fpath=(
  "${XDG_DATA_HOME:-$HOME/.local/share}/trove/completions"
  "$ZDOTDIR/completions"
  $fpath
)
fpath=(${^fpath}(N-/))

# Cache the compdump under XDG instead of dropping ~/.zcompdump in $HOME.
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-${ZSH_VERSION}"
[ -d "${_zcompdump:h}" ] || mkdir -p "${_zcompdump:h}"

autoload -Uz compinit
compinit -d "$_zcompdump"
unset _zcompdump

# Re-assert trove's handler in case something else grabbed the name.
(( $+functions[_trove] )) && compdef _trove trove

# bun ships its completion as a plain script to source, not an fpath function.
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
