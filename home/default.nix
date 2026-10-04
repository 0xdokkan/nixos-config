{ ... }:

{
  imports = [
    ./desktop.nix   # niri, dotfiles, tool del desktop wayland
    ./noctalia.nix  # shell condivisa: barra, launcher, lock e Tokyo Night Storm
    ./noctalia-idle.nix # tempi AC/batteria, senza sospendere i lavori CLI
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
