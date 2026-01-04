alias vim=nvim
alias vi=nvim
alias ls='ls --color=auto'

if command -v oh-my-posh >/dev/null 2>&1; then
  if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
    eval "$(oh-my-posh init zsh)"
  fi

  eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/config.json)"
fi

bindkey "^[[H" beginning-of-line
bindkey "^[[F" end-of-line

if [ -f "$HOME/.zshrc-custom" ]; then
  source $HOME/.zshrc-custom
fi
