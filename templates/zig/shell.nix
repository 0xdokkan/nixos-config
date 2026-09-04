# devshell Zig
{ pkgs }:

pkgs.mkShell {
  packages = with pkgs; [
    zig
    zls     # LazyVim extras.lang.zig
    gdb
  ];
}
