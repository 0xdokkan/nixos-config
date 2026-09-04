# devshell Python — le librerie le dichiari QUI (da nixpkgs), non con pip.
# Per un pacchetto che nixpkgs non ha: `uv venv && uv pip install X`
# funziona lo stesso grazie a programs.nix-ld (le wheel binarie partono).
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
}
