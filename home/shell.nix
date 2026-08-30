{ pkgs, ... }:

{
  # ══ zsh — casa tua, come su Arch ════════════════════════════════════
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];   # TODO: i plugin che usi davvero
    };

    # powerlevel10k: il TEMA lo installa nix...
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    # ...la TUA config p10k e il resto del .zshrc li porti tu:
    initContent = ''
      [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
      # TODO: migra qui alias/export/funzioni dal tuo .zshrc,
      # pezzo per pezzo — è l'occasione per buttare i fossili 😄
    '';
  };

  # ═══ ATTENZIONE: NON copiare il tuo .zshrc di Arch com'è! ═══════════
  # Su NixOS ~/.zshrc lo GENERA home-manager dalle opzioni qui sopra:
  # il bootstrap (source di oh-my-zsh, caricamento tema p10k, plugin)
  # è già gestito. Migra SOLO la parte personale — alias, export,
  # funzioni — in uno di questi due modi:
  #  - direttamente dentro initContent qui sopra, oppure
  #  - in dotfiles/zsh/extra.zsh, e in initContent aggiungi la riga:
  #      source ${../dotfiles/zsh/extra.zsh}
  # (l'instant prompt di p10k, se lo usi, va in CIMA al file generato:
  #  wrappa quel blocco con lib.mkBefore in un initContent separato)

  # TODO: copia il tuo ~/.p10k.zsh in dotfiles/zsh/p10k.zsh e scommenta:
  home.file.".p10k.zsh".source = ../dotfiles/zsh/p10k.zsh;

  # ══ CLI belt — i moduli HM si agganciano a zsh da soli ══════════════
  programs.zoxide.enable = true;
  programs.eza.enable = true;
  programs.fastfetch.enable = true;
  programs.yazi.enable = true;

  home.packages = with pkgs; [
    fd
    jq
    htop
    tealdeer
    parallel
    # TODO: pokemon-colorscripts? cerca su search.nixos.org 👀
  ];
}
