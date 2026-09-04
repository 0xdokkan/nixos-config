{ config, lib, pkgs, ... }:

{
  programs.git = {
    enable = true;
    # (HM recente: userName/userEmail sono diventati settings.user.*)
    settings.user = {
      name = "Dokkan";
      email = "ashigaruimpero@gmail.com";
    };
    # settings.init.defaultBranch = "main";
    # era ~/.config/git/ignore
    ignores = [ "**/.claude/settings.local.json" ];
  };

  # gh + credential helper per github.com e gist.github.com, come su Arch
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
  };

  programs.lazygit.enable = true;

  # direnv: entri nella cartella di un progetto con `.envrc` (`use flake`)
  # e la devshell si carica da sola. Vedi templates/c nel flake.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;   # era `alias vim=nvim` nel .zshrc
    # Tool iniettati nel PATH di nvim (e SOLO di nvim, via wrapper):
    extraPackages = with pkgs; [
      # treesitter compila i parser a runtime → gli serve un compiler
      gcc
      gnumake
      # nvim-treesitter (branch main) installa i parser tramite la CLI
      tree-sitter
      # telescope & co.
      ripgrep
      fd
      # ── LSP/tool "da editor", non legati a un progetto ──
      lua-language-server   # per la config di nvim stessa
      nil                   # Nix (extras.lang.nix è in lazyvim.json)
      stylua                # formatter lua (LazyVim lo vorrebbe da mason)
      # I toolchain-LSP (clangd, gopls, rust-analyzer, jdtls...) vivono
      # nelle devshell per-progetto insieme al compiler: nvim li trova nel
      # PATH quando lo apri da dentro `nix develop` / direnv.
    ];
  };

  # ══ La config nvim: strategia (B), symlink "live" DENTRO il repo ═════
  # LazyVim/lazy.nvim scrivono lazy-lock.json e i plugin li scaricano loro
  # in ~/.local/share/nvim: con il file nello store (read-only) il lockfile
  # non sarebbe scrivibile e ogni tweak = rebuild. Così invece editi al
  # volo e resta comunque versionato. Richiede il repo in ~/nixos-config.
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/nixos-config/dotfiles/nvim";
  # programs.neovim genera un suo ~/.config/nvim/init.lua (contiene solo
  # `vim.g.loaded_*_provider=0`): con la cartella intera symlinkata sopra
  # il build fallisce ("file outside $HOME"). Lo spegniamo: l'init.lua
  # vero è quello di LazyVim. Se :checkhealth si lamenta dei provider
  # python/ruby/node/perl, metti quelle righe in lua/config/options.lua.
  xdg.configFile."nvim/init.lua".enable = lib.mkForce false;

  # 🚩 gef dentro gdb — anche quando pwntools fa gdb.attach() e lancia
  # `gdb` liscio. (Era `source /usr/share/gef/gef.py` su Arch.)
  home.file.".gdbinit".text = "source ${pkgs.gef}/share/gef/gef.py";

  home.packages = with pkgs; [
    # ── agenti AI da terminale (i client desktop: vedi README) ──
    claude-code   # Claude Code
    codex         # OpenAI Codex CLI
    opencode
    # ═══ DOTTRINA DEVSHELL ═══════════════════════════════════════════
    # NIENTE toolchain globali qui! go/rustup/jdk/python/meson/raylib/
    # odin/bullet vivono nei `nix develop` per-progetto.
    # Pronti nel flake.nix di questo repo:
    #   - scratch, da ovunque:  nix develop ~/nixos-config#c   (o rust/zig/python/ctf)
    #   - nuovo progetto:       nix flake init -t ~/nixos-config#c && direnv allow
    # postgresql: idem, per-progetto con PGDATA=./.pgdata (git-ignorato).
    # ═════════════════════════════════════════════════════════════════
  ];
}
