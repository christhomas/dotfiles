# History — keep it under XDG rather than $HOME.
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=50000
SAVEHIST=50000
[ -d "${HISTFILE:h}" ] || mkdir -p "${HISTFILE:h}"

setopt EXTENDED_HISTORY        # record timestamps
setopt INC_APPEND_HISTORY      # write as you go, not only on exit
setopt SHARE_HISTORY           # share between concurrent shells
setopt HIST_IGNORE_ALL_DUPS    # keep only the newest copy of a duplicate
setopt HIST_IGNORE_SPACE       # leading space keeps a command out of history
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY             # expand !! for review instead of running it

setopt AUTO_CD                 # `foo` == `cd foo` when foo is a directory
setopt INTERACTIVE_COMMENTS    # allow # comments at the prompt
setopt NO_BEEP
