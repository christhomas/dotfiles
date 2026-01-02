alias vim=nvim
alias vi=nvim
alias ls='ls --color=auto'

if command -v oh-my-posh; then
  if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
    eval "$(oh-my-posh init zsh)"
  fi

  eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/config.json)"
fi

bindkey "^[[H" beginning-of-line
bindkey "^[[F" end-of-line

# Added by Windsurf - Next
export PATH="/Users/chris/.codeium/windsurf/bin:$PATH"

# opencode
export PATH=/Users/christhomas/.opencode/bin:$PATH

# pnpm
export PNPM_HOME="/Users/christhomas/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

if [ -f "$HOME/.zshrc-custom" ]; then
  source $HOME/.zshrc-custom
fi
