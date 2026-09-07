{
  description = "Sistema NixOS di Dokkan — il rice come sorgente";

  # Vale già al primo rebuild (previa accettazione della config del flake).
  # La stessa cache è configurata nel sistema in hosts/common.nix.
  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  # ── Gli input: pochi e giustificati. Resisti all'input creep! ──
  #   nixpkgs + home-manager: la base.
  #   helium-flake: Helium non è in nixpkgs (upstream pubblica solo .deb),
  #                 questo flake lo estrae e lo patcha. Voluto. :3
  #   llm-agents: ultime release delle CLI e app AI, aggiornabili da sole.
  #   (DMS è in nixpkgs da 26.05: niente input per lui ✓)
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      # single source of truth: home-manager usa il NOSTRO nixpkgs
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helium-flake = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Niente follows: conserva il nixpkgs testato da Numtide e i cache hit,
    # anche quando aggiorni solo questo input senza aggiornare il sistema.
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, home-manager, helium-flake, llm-agents, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # le devshell dei template sono funzioni { pkgs } → mkShell:
      # le stesse identiche shell le esponiamo anche qui per uso "scratch"
      shell = name: import ./templates/${name}/shell.nix { inherit pkgs; };

      # Un host = hosts/<nome>/configuration.nix (+ ../common.nix dentro)
      # con la STESSA home di dokkan agganciata.
      mkHost = name: nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./hosts/${name}/configuration.nix

          # home-manager come modulo NixOS: sistema e home si buildano
          # e switchano INSIEME, atomicamente, in un solo comando
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs.aiPackages = llm-agents.packages.${system};
            home-manager.users.dokkan = import ./home;
            # moduli HM esterni, disponibili a tutti i file in home/
            home-manager.sharedModules = [
              helium-flake.homeModules.default   # programs.helium.*
            ];
            # se un rebuild trova dotfiles pre-esistenti non gestiti,
            # invece di fallire li salva con questo suffisso:
            home-manager.backupFileExtension = "hm-backup";
          }
        ];
      };
    in
    {
      # ── I sistemi: `sudo nixos-rebuild switch --flake .#<nome>` ──
      nixosConfigurations = {
        armoredcoreVIP = mkHost "armoredcoreVIP";   # ThinkPad T470s, Intel
        armoredcoreVIF = mkHost "armoredcoreVIF";   # il fisso: RTX 2070 nvidia
      };

      # ── `nix flake check`: config niri, regressioni e impostazioni desktop ──
      # niri-config è la stessa derivazione linkata da home/desktop.nix.
      checks.${system} = {
        niri-config = import ./home/niri-configs.nix { inherit pkgs; };
        niri-regressions =
          let
            laptopNiri = import ./home/niri-configs.nix { inherit pkgs; layout = "it"; };
          in
          pkgs.runCommand "niri-regressions-checked" {
            nativeBuildInputs = [ pkgs.python3 ];
          } ''
            python ${./tests/niri-regressions.py} \
              ${self.checks.${system}.niri-config}/config.kdl \
              ${laptopNiri}/config.kdl
            touch "$out"
          '';
        niri-gamemode = import ./tests/gamemode.nix { inherit pkgs; };

        # Verifica i font realmente risolti e i file generati, senza attivare
        # la home o dipendere dai font della macchina che esegue il check.
        desktop-settings =
          let
            laptop = self.nixosConfigurations.armoredcoreVIP.config;
            home = laptop.home-manager.users.dokkan;
            fontTestConfig = pkgs.writeText "monaspace-test.conf" ''
              <?xml version="1.0"?>
              <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
              <fontconfig>
                <dir>${pkgs.monaspace}/share/fonts</dir>
                <include>${laptop.environment.etc.fonts.source}/conf.d/52-nixos-default-fonts.conf</include>
                <cachedir prefix="xdg">fontconfig</cachedir>
              </fontconfig>
            '';
          in
          assert laptop.services.upower.enable;
          assert home.gtk.font.name == "Monaspace Argon";
          assert home.qt.platformTheme.name == "qtct";
          assert laptop.environment.sessionVariables.QT_QPA_PLATFORMTHEME == home.home.sessionVariables.QT_QPA_PLATFORMTHEME;
          pkgs.runCommand "desktop-settings-checked" {
            nativeBuildInputs = [ pkgs.fontconfig pkgs.jq pkgs.ripgrep ];
            FONTCONFIG_FILE = fontTestConfig;
          } ''
            export XDG_CACHE_HOME="$TMPDIR/font-cache"
            for family in sans-serif monospace; do
              test "$(fc-match --format '%{family}' "$family")" = 'Monaspace Argon'
            done
            jq -e '.fontFamily == "Monaspace Argon" and .monoFontFamily == "Monaspace Argon" and .fontWeight == 400 and .qtThemingEnabled == false' \
              ${./dotfiles/dms/settings.json}
            for ini in ${home.xdg.configFile."qt5ct/qt5ct.conf".source} ${home.xdg.configFile."qt6ct/qt6ct.conf".source}; do
              rg '^general\s*=\s*"Monaspace Argon,10"$' "$ini"
              rg '^fixed\s*=\s*"Monaspace Argon,10"$' "$ini"
            done
            for ini in ${home.xdg.configFile."gtk-3.0/settings.ini".source} ${home.xdg.configFile."gtk-4.0/settings.ini".source}; do
              rg '^gtk-font-name\s*=\s*Monaspace Argon 10$' "$ini"
            done
            touch "$out"
          '';
      };

      # ── Devshell "scratch": `nix develop ~/nixos-config#<nome>` da ovunque ──
      devShells.${system} = {
        # Le stesse shell dei template (templates/<nome>/shell.nix):
        # per provare due righe senza creare un progetto.
        c      = shell "c";
        rust   = shell "rust";
        zig    = shell "zig";
        python = shell "python";

        # Arsenale CTF 🚩 (gef è già caricato da ~/.gdbinit, vedi home/dev.nix)
        ctf = pkgs.mkShell {
          packages = with pkgs; [
            # pwn
            gdb
            gef
            pwninit          # patchelf + libc + template exploit in un colpo
            patchelf
            ropgadget
            one_gadget
            (python3.withPackages (ps: with ps; [
              pwntools
              pycryptodome
              ipython
            ]))
            # reversing / forensics
            radare2
            binwalk
            file
            hexyl
            strace
            ltrace
            # rete (la GUI di wireshark è a sistema in programs.wireshark)
            termshark
            wireshark-cli    # tshark
            netcat-openbsd
            socat
            nmap
            # ghidra   # ~1 GB: scommenta quando ti serve davvero
          ];
        };
      };

      # ── Template per i progetti: ogni repo ha il SUO flake + devshell ──
      # Nella cartella del nuovo progetto:
      #     nix flake init -t ~/nixos-config#c && direnv allow
      # (o #rust, #zig, #python). Poi editi templates/<nome>/shell.nix
      # copiato nel progetto per aggiungere librerie. I toolchain non
      # toccano mai il sistema.
      templates = {
        c = {
          path = ./templates/c;
          description = "devshell C: gcc/meson/ninja/clangd/gdb + raylib e bullet";
        };
        rust = {
          path = ./templates/rust;
          description = "devshell Rust: cargo/rustc/rust-analyzer/clippy (stable da nixpkgs)";
        };
        zig = {
          path = ./templates/zig;
          description = "devshell Zig: zig + zls";
        };
        python = {
          path = ./templates/python;
          description = "devshell Python: interprete con librerie da nixpkgs, pyright, ruff, uv";
        };
      };
    };
}
