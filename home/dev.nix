{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "TODO";
    userEmail = "todo@todo.dev";
    # extraConfig = { init.defaultBranch = "main"; };
  };

  programs.lazygit.enable = true;

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    # Tool iniettati nel PATH di nvim (e SOLO di nvim, via wrapper):
    extraPackages = with pkgs; [
      # treesitter compila i parser a runtime → gli serve un compiler
      gcc
      gnumake
      # telescope & co.
      ripgrep
      fd
      # ── LSP dal nixpkgs invece che da mason (migrazione graduale) ──
      # lua-language-server
      # nil                  # LSP per il Nix che stai per scrivere :3
      # clang-tools          # clangd per i progetti C
      # gopls
    ];
  };

  # ══ La config nvim: copia ~/.config/nvim → dotfiles/nvim, poi ═══════
  # ══ SCEGLI UNA delle due strategie e scommenta: ═════════════════════
  #
  # (A) gestita da nix, read-only dallo store — massima riproducibilità,
  #     MA lazy-lock.json non scrivibile e ogni tweak = rebuild:
  # xdg.configFile."nvim".source = ../dotfiles/nvim;
  #
  # (B) symlink "live" DENTRO il repo — editabile al volo, lazy scrive
  #     il lockfile, e resta comunque versionato su git.
  #     (richiede che il repo viva in ~/nixos-config)
  # xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink
  #   "${config.home.homeDirectory}/nixos-config/dotfiles/nvim";

  home.packages = with pkgs; [
    gh
    # ═══ DOTTRINA DEVSHELL ═══════════════════════════════════════════
    # NIENTE toolchain globali qui! go/rustup/jdk/python/meson/raylib/
    # odin/bullet vivono nei `nix develop` per-progetto.
    # Esempio già pronto: devShells.ctf nel flake.nix di questo repo.
    # postgresql: idem, per-progetto con PGDATA=./.pgdata (git-ignorato).
    # ═════════════════════════════════════════════════════════════════
  ];
}
