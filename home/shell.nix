{ config, pkgs, ... }:

let
  fastfetchSpin = import ./fastfetch-spin.nix { inherit pkgs; };
in
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
  # fastfetch: config in dotfiles/fastfetch/config.jsonc. Il logo è il
  # fiocco NixOS 3D di fastfetch-spin.nix: `fastfetch` senza argomenti lo
  # fa girare, altrimenti è il logo statico (@LOGO@ nel jsonc). Le immagini
  # restano in dotfiles/fastfetch/images/ (@IMAGES@, vedi il commento lì).
  programs.fastfetch = {
    enable = true;
    package = fastfetchSpin;
  };
  xdg.configFile."fastfetch/config.jsonc".source =
    pkgs.replaceVars ../dotfiles/fastfetch/config.jsonc {
      IMAGES = "${../dotfiles/fastfetch/images}";
      LOGO = builtins.toJSON fastfetchSpin.logo;
    };
  programs.yazi.enable = true;   # la zsh integration genera la funzione `y`

  # Il sostituto del command_not_found_handler basato su `pacman -F`:
  # "comando X non trovato → è nel pacchetto Y". Il modulo HM di
  # nix-index-database fornisce già il DB: niente generazione al primo boot.
  # L'indice segue la revisione dell'input nel flake.lock.
  programs.nix-index.enable = true;
  programs.nix-index.enableZshIntegration = true;

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
