{ pkgs }:

let
  snapshot = pkgs.writeTextDir "flake.nix" "{ outputs = _: {}; }";
in
pkgs.runCommand "nixup-checked" {
  nativeBuildInputs = [
    pkgs.bashNonInteractive
    pkgs.coreutils
    pkgs.git
    pkgs.jq
    pkgs.util-linux
    pkgs.python3
  ];
} ''
  # Nix, nvd, sudo e il nome host sono sostituiti dagli stub del test.
  # Git/flock/jq restano reali. Il dispatcher nixos-rebuild bloccato dal flake
  # viene importato con build e attivazione intercettate: niente rete o switch.
  python ${./nixup.py} ${../home/nixup.sh} ${snapshot} ${pkgs.nixos-rebuild.src}
  touch "$out"
''
