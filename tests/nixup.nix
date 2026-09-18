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
  # Git/flock/jq restano reali; non si contatta la rete e non si attiva NixOS.
  python ${./nixup.py} ${../home/nixup.sh} ${snapshot}
  touch "$out"
''
