{ config, pkgs, ... }:

{
  # ══ zsh — casa tua, come su Arch ════════════════════════════════════
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;       # era il plugin zsh-autosuggestions
    syntaxHighlighting.enable = true;   # era il plugin zsh-syntax-highlighting

    oh-my-zsh = {
      enable = true;
      # (zsh-256color non è un plugin omz: su Arch era un pacchetto a parte
      #  e kitty dichiara già TERM=xterm-kitty a 256 colori)
      plugins = [ "git" "sudo" ];
    };

    # powerlevel10k: il TEMA lo installa nix...
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    # ...la config p10k e la parte personale del .zshrc sono in dotfiles/zsh/
    initContent = ''
      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
      source ${../dotfiles/zsh/extra.zsh}
    '';
  };

  # ═══ Perché NON c'è il .zshrc di Arch com'era ═══════════════════════
  # Su NixOS ~/.zshrc lo GENERA home-manager dalle opzioni qui sopra:
  # source di oh-my-zsh, tema p10k, plugin, integrazioni (zoxide, yazi,
  # direnv, nix-index...) sono già gestiti. In dotfiles/zsh/extra.zsh c'è
  # SOLO la parte personale (alias, pokemon); in testa al file è annotato
  # dove è finito ogni pezzo pacman-specifico che è stato buttato.

  # la config p10k (identica a ~/.p10k.zsh di Arch)
  home.file.".p10k.zsh".source = ../dotfiles/zsh/p10k.zsh;

  # era `export PATH="$HOME/.local/bin:$PATH"` nel .zshrc
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  # ══ CLI belt — i moduli HM si agganciano a zsh da soli ══════════════
  programs.zoxide.enable = true;
  programs.eza = {
    enable = true;
    # gli alias li definisce extra.zsh (come su Arch), non HM
    enableZshIntegration = false;
  };
  programs.fastfetch.enable = true;
  programs.yazi.enable = true;   # la zsh integration genera la funzione `y`

  # Il sostituto del command_not_found_handler basato su `pacman -F`:
  # "comando X non trovato → è nel pacchetto Y". Serve il DB: dopo il
  # primo boot lancia `nix-index` una volta (ci mette qualche minuto).
  programs.nix-index.enable = true;

  home.packages = with pkgs; [
    fd
    jq
    htop
    tealdeer
    parallel
    # quello VERO in python (come pokemon-colorscripts-git su Arch): capisce
    # `--no-title -r 1,3,6` di extra.zsh. NON `pokemon-colorscripts-mac`: è
    # la vecchia versione bash, senza filtro generazioni → "too many arguments"
    pokemon-colorscripts
  ];
}
