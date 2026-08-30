{ pkgs, ... }:

{
  # ══ niri: il tuo config.kdl, intonso, validato a BUILD-TIME ═════════
  # Se la config è invalida, il sistema si rifiuta di buildare. ✨
  xdg.configFile."niri/config.kdl".source =
    pkgs.runCommand "niri-config-checked"
      { nativeBuildInputs = [ pkgs.niri ]; } ''
      niri validate --config ${../dotfiles/niri/config.kdl}
      cp ${../dotfiles/niri/config.kdl} $out
    '';

  # Gli script che config.kdl chiama (dontkillsteam.sh & co.)
  # → copiali in dotfiles/niri/scripts/ con l'exec bit (vedi README lì)
  xdg.configFile."niri/scripts" = {
    source = ../dotfiles/niri/scripts;
    recursive = true;
  };

  # ══ Gli attrezzi wayland che config.kdl / il tuo workflow usano ═════
  home.packages = with pkgs; [
    # screenshot pipeline (bind Mod+Ctrl+P)
    grim
    slurp
    swappy
    # clipboard (spawn-at-startup usa wl-paste! è nel pacchetto wl-clipboard)
    wl-clipboard
    cliphist
    # colore/luminosità/audio
    wl-gammarelay
    brightnessctl
    pamixer
    pavucontrol
    # dischi removibili (il client; il demone udisks2 è a sistema)
    udiskie
    # notifiche da script
    libnotify
    # TODO: le tue app — firefox, librewolf, webcord, obsidian, anki,
    # calibre, qbittorrent, gimp, kitty è sotto come programs.kitty...
  ];

  # ══ Terminale ═══════════════════════════════════════════════════════
  programs.kitty.enable = true;
  # TODO: porta la tua config — o via opzioni HM (programs.kitty.settings)
  # o linkando il file com'è:
  # xdg.configFile."kitty/kitty.conf".source = ../dotfiles/kitty/kitty.conf;

  # ══ Gli altri dotfiles, stesso pattern del link ═════════════════════
  # TODO: copia le cartelle in dotfiles/ e scommenta man mano
  # xdg.configFile."hyprlock".source = ../dotfiles/hyprlock;
  # xdg.configFile."cava".source = ../dotfiles/cava;
  # xdg.configFile."fastfetch".source = ../dotfiles/fastfetch;
  # home.file.".gdbinit".source = ../dotfiles/gdb/gdbinit;   # 🚩
}
