# devshell Python — le librerie le dichiari QUI (da nixpkgs), non con pip.
# Per un pacchetto che nixpkgs non ha:
#   uv venv --python python3 && uv pip install X
# Le wheel con estensioni native possono richiedere librerie condivise extra.
# Python di nixpkgs usa il loader dello store, quindi nix-ld non interviene:
# dichiara le librerie necessarie nella devshell (esempio sotto), per progetto.
# https://github.com/nix-community/nix-ld#my-pythonnodejsrubyinterpreter-libraries-do-not-find-the-libraries-configured-by-nix-ld
{ pkgs }:

pkgs.mkShell {
  packages = with pkgs; [
    (python3.withPackages (ps: with ps; [
      # ── aggiungi/togli per progetto ──
      numpy
      pillow
      requests
      ipython
    ]))
    # LazyVim extras.lang.python: LSP + linter/formatter
    pyright
    ruff
    # per i pacchetti fuori da nixpkgs (vedi sopra)
    uv
  ];

  # Solo se una wheel richiede queste librerie; adatta la lista al progetto.
  # LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc pkgs.zlib ];
}
