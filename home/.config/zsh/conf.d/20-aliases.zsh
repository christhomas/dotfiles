alias vim=nvim
alias vi=nvim

# BSD ls (macOS) has no --color=auto; it spells the same thing -G.
if ls --color=auto >/dev/null 2>&1; then
  alias ls='ls --color=auto'
else
  alias ls='ls -G'
fi

alias claude-mem='bun "$HOME/.claude/plugins/marketplaces/thedotmack/plugin/scripts/worker-service.cjs"'
alias claude-ct='CLAUDE_CONFIG_DIR="$HOME/.claude-ct" claude'
alias claude-wk='CLAUDE_CONFIG_DIR="$HOME/.claude-wk" claude'

