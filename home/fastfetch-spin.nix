{ pkgs, fastfetch ? pkgs.fastfetch }:

let
  # Il fiocco occupa 44x20 celle (le celle sono alte il doppio della
  # larghezza). 72 fotogrammi = 5 gradi l'uno; 2 giri in 3 secondi.
  width = 44;
  height = 20;
  count = 72;
  padding = { top = 1; left = 2; right = 3; };

  # I fotogrammi si calcolano una volta sola, al build: a runtime il player
  # li ristampa e basta (niente Python o numpy nel PATH).
  frames = pkgs.runCommand "nix-snowflake-3d-frames" {
    nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.numpy ])) ];
  } ''
    python ${./fastfetch-spin.py} --width ${toString width} \
      --height ${toString height} --frames ${toString count} \
      --spins 2 --seconds 3 --out "$out"
  '';

  player = pkgs.writeShellApplication {
    name = "fastfetch";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      readonly SPIN_REAL=${fastfetch}/bin/fastfetch
      readonly SPIN_FRAMES=${frames}/frames.txt
      readonly SPIN_SCHEDULE=${frames}/schedule.txt
      readonly SPIN_WIDTH=${toString width}
      readonly SPIN_HEIGHT=${toString height}
      readonly SPIN_COUNT=${toString count}
      readonly SPIN_PAD_TOP=${toString padding.top}
      readonly SPIN_PAD_LEFT=${toString padding.left}
      readonly SPIN_PAD_RIGHT=${toString padding.right}
      ${builtins.readFile ./fastfetch-spin.sh}
    '';
  };
in
# Il pacchetto fastfetch completo (man, completion, flashfetch) con il solo
# bin/fastfetch sostituito dal player.
pkgs.symlinkJoin {
  name = "fastfetch-spin-${fastfetch.version or "0"}";
  paths = [ fastfetch ];
  postBuild = ''
    rm "$out/bin/fastfetch"
    ln -s ${player}/bin/fastfetch "$out/bin/fastfetch"
  '';
  passthru = {
    inherit frames player width height count;
    unwrapped = fastfetch;
    # Il blocco "logo" di config.jsonc: stesso fiocco, statico, stessi margini.
    logo = {
      type = "file-raw";
      source = "${frames}/logo.txt";
      inherit width height padding;
    };
  };
  meta.mainProgram = "fastfetch";
}
