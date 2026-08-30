{ ... }:

{
  imports = [
    ./desktop.nix   # niri, dotfiles, tool del desktop wayland
    ./shell.nix     # zsh + p10k + CLI belt
    ./dev.nix       # git, editor, dev quotidiano
  ];

  home.username = "dokkan";
  home.homeDirectory = "/home/dokkan";

  # lascia che home-manager gestisca sé stesso
  programs.home-manager.enable = true;

  # Stesso discorso di system.stateVersion: si fissa e non si tocca più.
  home.stateVersion = "26.05";
}
