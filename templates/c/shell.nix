# devshell C — usata sia da `nix develop ~/nixos-config#c` (scratch)
# sia dal flake.nix di ogni progetto creato col template.
{ pkgs }:

pkgs.mkShell {
  packages = with pkgs; [
    # toolchain
    gcc
    gnumake
    meson
    ninja
    pkg-config
    # editor: clangd per LazyVim (extras.lang.clangd) + clang-format
    clang-tools
    # debug
    gdb
    valgrind
    # librerie dell'engine — togli/aggiungi per progetto
    raylib
    bullet
  ];
}
