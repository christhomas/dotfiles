# Auto-start tmux. Sessions are grouped: every terminal attaches to the same
# session group ("window") but gets an independent view of it.
if command -v tmux >/dev/null 2>&1 \
  && [[ -z "$TMUX" ]] \
  && [[ -t 0 ]] \
  && [[ "$TERM_PROGRAM" != "vscode" ]]; then
  if tmux has-session -t window 2>/dev/null; then
    i=1
    while tmux has-session -t "window-$i" 2>/dev/null; do ((i++)); done
    exec tmux new-session -t window -s "window-$i"
  else
    exec tmux new-session -s window
  fi
fi
