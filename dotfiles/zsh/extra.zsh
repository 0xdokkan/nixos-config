# ── alias & funzioni personali — sourced da home/shell.nix ─────────────
# Portati dal .zshrc di Arch. Quello che NON c'è più, e dove è finito:
#   - command_not_found_handler (pacman -F) → programs.nix-index (shell.nix)
#   - in / un / up / pl / pa / pc / po      → pacman/paru, non esistono qui
#   - y() di yazi                           → la genera programs.yazi (HM)
#   - alias vim=nvim                        → programs.neovim.vimAlias (dev.nix)
#   - export PATH=~/.local/bin:$PATH        → home.sessionPath (shell.nix)
#   - $(go env GOPATH)/bin nel PATH         → go vive nelle devshell per-progetto

# eza (programs.eza è attivo ma con la zsh integration spenta,
# così questi alias non litigano con quelli generati da HM)
alias c='clear'
alias l='eza -lh  --icons=auto'
alias ls='eza -1   --icons=auto'
alias ll='eza -lha --icons=auto --sort=name --group-directories-first'
alias ld='eza -lhD --icons=auto'
alias lt='eza --icons=auto --tree'

# cd rapidi
alias ..='cd ..'
alias ...='cd ../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias .5='cd ../../../../..'

# mkdir crea sempre tutto il path
alias mkdir='mkdir -p'

# Pokémon all'apertura del terminale (random tra gen 1, 3 e 6)
pokemon-colorscripts --no-title -r 1,3,6
