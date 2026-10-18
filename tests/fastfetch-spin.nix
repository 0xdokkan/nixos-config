{ pkgs }:

let
  # Al posto di fastfetch: info fisse, e "REAL <argomenti>" per il resto.
  fakeFastfetch = pkgs.writeShellScriptBin "fastfetch" ''
    if [ "$*" = "--logo none --pipe false" ]; then
      printf '\033[?7l'
      i=1
      while [ "$i" -le 24 ]; do
        printf 'info line %02d\n' "$i"
        i=$((i + 1))
      done
      printf '\033[?7h'
    else
      printf 'REAL %s\n' "$*"
    fi
  '';
  # Stessi fotogrammi e stesso player del pacchetto vero.
  spin = import ../home/fastfetch-spin.nix { inherit pkgs; fastfetch = fakeFastfetch; };
in
pkgs.runCommand "fastfetch-spin-checked" {
  nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils ];
} ''
  python ${./fastfetch-spin.py} ${spin}/bin/fastfetch ${spin.frames} \
    ${pkgs.coreutils}/bin/stty ${toString spin.width} ${toString spin.height} \
    ${toString spin.count} ${toString spin.logo.padding.top} \
    ${toString spin.logo.padding.left} ${toString spin.logo.padding.right}
  touch "$out"
''
