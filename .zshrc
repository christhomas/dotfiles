alias vim=nvim
alias vi=nvim

if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "$(oh-my-posh init zsh)"
fi

eval "$(oh-my-posh init zsh --config $HOME/.config/ohmyposh/config.json)"

bindkey "^[[H" beginning-of-line
bindkey "^[[F" end-of-line
