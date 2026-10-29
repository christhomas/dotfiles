# $ZDOTDIR/.zshrc — interactive shells.
# This file is only a loader; real config lives in $ZDOTDIR/conf.d/*.zsh,
# sourced in filename order. Add a numbered file there rather than editing this.

[[ -o interactive ]] || return

for _zrc in "$ZDOTDIR"/conf.d/*.zsh(N); do
  source "$_zrc"
done
unset _zrc

# Per-machine overrides (not tracked by dotman). Loaded last so it wins.
[ -f "$ZDOTDIR/.zshrc.local" ] && source "$ZDOTDIR/.zshrc.local"

# bun completions
[ -s "/Users/christhomas/.bun/_bun" ] && source "/Users/christhomas/.bun/_bun"
