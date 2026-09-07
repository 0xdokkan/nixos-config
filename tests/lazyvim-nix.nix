{ pkgs }:

pkgs.runCommand "lazyvim-nix-checked" {
  nativeBuildInputs = [ pkgs.luajit ];
} ''
  luajit ${./lazyvim-nix.lua} ${../dotfiles/nvim/lua/plugins/nix.lua}
  touch "$out"
''
