# attic

Pre-migration zsh files, kept for reference only.

Superseded on 2026-09-13 by the XDG layout: `home/.zshenv` sets `ZDOTDIR` to
`~/.config/zsh`, and the real config lives in `home/.config/zsh/`
(`.zprofile`, `.zshrc`, `conf.d/*.zsh`).

These live outside `home/`, so `dotman apply` ignores them. Delete this
directory once you're satisfied nothing here is still needed.

- `.zshrc`       — old interactive config; split into `conf.d/*.zsh`
- `.zprofile`    — old PATH/env; now `home/.config/zsh/.zprofile`
- `.zshprofile`  — legacy duplicate of `.zprofile`, minus the `.local/bin` entry
