{ ... }:

{
  imports = [
    ./desktop.nix   # app, GTK/Qt, cursore, kitty e altri dotfiles
    ./mango.nix     # il compositor: config validata, sessione systemd
    ./waybar.nix    # la barra
    ./rofi.nix      # launcher e menu (wifi, bluetooth, Wi-Fi QR)
    ./notifications.nix # swaync (notifiche, centro di controllo) e swayosd
    ./lock.nix      # hyprlock e idle AC/batteria
    ./session.nix   # polkit, appunti, sfondo, luce notturna, dischi, batteria
    ./shell.nix     # zsh + p10k + CLI belt
    ./dev.nix       # git, editor, dev quotidiano
    ./maintenance.nix # aggiornamento assistito del sistema (nixup)
  ];

  home.username = "dokkan";
  home.homeDirectory = "/home/dokkan";

  # lascia che home-manager gestisca sé stesso
  programs.home-manager.enable = true;

  # Stesso discorso di system.stateVersion: si fissa e non si tocca più.
  home.stateVersion = "26.05";
}
