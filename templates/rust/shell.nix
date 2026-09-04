# devshell Rust — toolchain STABILE da nixpkgs (niente rustup: su NixOS
# i toolchain scaricati da rustup non trovano le librerie di sistema).
# Se un giorno ti serve nightly: input `oxalica/rust-overlay` o `fenix`.
{ pkgs }:

pkgs.mkShell {
  packages = with pkgs; [
    cargo
    rustc
    rust-analyzer   # LazyVim extras.lang.rust
    clippy
    rustfmt
    # crate con dipendenze C (openssl-sys & co.) le trovano così:
    pkg-config
    openssl
    gdb
  ];

  # rust-analyzer vuole i sorgenti della std
  RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
}
