{
  description = "Sistema NixOS di Dokkan — il rice come sorgente";

  # Vale già al primo rebuild (previa accettazione della config del flake).
  # La stessa cache è configurata nel sistema in hosts/common.nix.
  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  # ── Gli input: pochi e giustificati. Resisti all'input creep! ──
  #   nixpkgs + home-manager: la base.
  #   helium-flake: Helium non è in nixpkgs (upstream pubblica solo .deb),
  #                 questo flake lo estrae e lo patcha. Voluto. :3
  #   llm-agents: ultime release delle CLI e app AI, aggiornabili da sole.
  #   nix-index-database: indice precompilato per i comandi non trovati.
  #   noctalia: release 5.2.1, compilata col nixpkgs del sistema.
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      # single source of truth: home-manager usa il NOSTRO nixpkgs
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helium-flake = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Niente follows: conserva il nixpkgs testato da Numtide e i cache hit,
    # anche quando aggiorni solo questo input senza aggiornare il sistema.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Release esplicita: niente salto involontario a nuove major/API IPC.
    # follows: con la patch locale il binario non è mai nella cache upstream,
    # quindi si compila comunque. Con il nostro nixpkgs almeno glibc e PAM
    # sono quelli del sistema: il lockscreen carica in-process i moduli PAM
    # di NixOS, che con una glibc più vecchia potrebbero non caricarsi.
    noctalia = {
      url = "github:noctalia-dev/noctalia/v5.2.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nix-index-database, helium-flake, llm-agents, noctalia, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # La 5.2.1 espone solo il toggle manuale: due IPC additivi conservano
      # Alt+F8 = acceso / Alt+F9 = spento anche fuori dagli orari programmati.
      noctaliaSource = pkgs.applyPatches {
        name = "noctalia-5.2.1-source";
        src = noctalia.packages.${system}.default.src;
        patches = [ ./patches/noctalia-nightlight-ipc.patch ];
      };
      noctaliaPackage = noctalia.packages.${system}.default.overrideAttrs (_: {
        src = noctaliaSource;
      });
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
            home-manager.extraSpecialArgs = {
              inherit noctaliaPackage;
              aiPackages = llm-agents.packages.${system};
            };
            home-manager.users.dokkan = import ./home;
            # moduli HM esterni, disponibili a tutti i file in home/
            home-manager.sharedModules = [
              helium-flake.homeModules.default   # programs.helium.*
              nix-index-database.homeModules.default # nix-locate + DB pronto
            ];
            # se un rebuild trova dotfiles pre-esistenti non gestiti,
            # invece di fallire li salva con questo suffisso:
            home-manager.backupFileExtension = "hm-backup";
            # ...e se il backup esiste già (es. mimeapps.list riscritto due
            # volte da "imposta come predefinito") lo sovrascrive invece di
            # far fallire l'attivazione della home.
            home-manager.overwriteBackup = true;
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
            laptopNiri = import ./home/niri-configs.nix { inherit pkgs; layout = "it,us"; };
            # i host.kdl VERI che home-manager linka su ciascun host
            hostKdl = host:
              self.nixosConfigurations.${host}.config.home-manager.users.dokkan.xdg.configFile."niri/host.kdl".source;
            softwareCursorNiri = import ./home/niri-configs.nix {
              inherit pkgs;
              disableCursorPlane = true;
            };
          in
          pkgs.runCommand "niri-regressions-checked" {
            nativeBuildInputs = [ pkgs.python3 ];
          } ''
            python ${./tests/niri-regressions.py} \
              --noctalia-root ${noctaliaSource} \
              ${self.checks.${system}.niri-config}/config.kdl \
              ${laptopNiri}/config.kdl \
              ${softwareCursorNiri}/config.kdl
            python - ${self.checks.${system}.niri-config}/host.kdl \
              ${laptopNiri}/host.kdl ${softwareCursorNiri}/host.kdl \
              ${hostKdl "armoredcoreVIP"} ${hostKdl "armoredcoreVIF"} <<'PY'
            import sys
            from pathlib import Path
            desktop, laptop, workaround, real_vip, real_vif = (
                Path(p).read_text() for p in sys.argv[1:]
            )
            assert "disable-cursor-plane" not in desktop
            assert "disable-cursor-plane" not in laptop
            assert "disable-cursor-plane" in workaround
            # Portatile: it + us su Mod+K (solo niri). Fisso: solo us.
            assert 'layout "it,us"' in real_vip
            assert 'layout "us"' in real_vif
            assert "disable-cursor-plane" not in real_vip + real_vif
            PY
            touch "$out"
          '';
        niri-gamemode = import ./tests/gamemode.nix { inherit pkgs; };
        noctalia-idle = import ./tests/noctalia-idle.nix { inherit pkgs noctaliaSource; };
        noctalia-nightlight = pkgs.runCommand "noctalia-nightlight-checked" {
          nativeBuildInputs = [ pkgs.python3 pkgs.stdenv.cc ];
        } ''
          python ${./tests/noctalia-nightlight.py} ${noctaliaSource}
          touch "$out"
        '';
        noctalia-settings = import ./tests/noctalia-settings.nix {
          inherit pkgs noctaliaPackage;
          configFile = self.nixosConfigurations.armoredcoreVIP.config.home-manager.users.dokkan.xdg.configFile."noctalia/config.toml".source;
          paletteFile = ./dotfiles/noctalia/palettes/TokyoNightStorm.json;
        };
        noctalia-integration =
          let
            configs = map (host: self.nixosConfigurations.${host}.config)
              [ "armoredcoreVIP" "armoredcoreVIF" ];
            valid = c: let home = c.home-manager.users.dokkan; in
              !c.programs.dms-shell.enable
              && c.services.upower.enable
              && c.security.polkit.enable
              && c.services.power-profiles-daemon.enable
              && home.programs.noctalia.enable
              && home.programs.noctalia.systemd.enable
              && home.programs.noctalia.package.outPath == noctaliaPackage.outPath
              && home.programs.noctalia.settings.shell.polkit_agent
              && home.programs.noctalia.settings.lockscreen.enabled
              && home.programs.noctalia.settings.lockscreen.lock_before_suspend
              && !home.programs.noctalia.settings.idle.behavior.lock.enabled
              && !home.programs.noctalia.settings.idle.behavior.screen-off.enabled
              && !home.programs.noctalia.settings.idle.behavior.suspend.enabled
              && !home.programs.noctalia.settings.idle.behavior.lock-and-suspend.enabled
              && home.systemd.user.services ? noctalia-idle
              && home.xdg.desktopEntries ? noctalia-wifi-qr
              && !(home.xdg.configFile ? DankMaterialShell);
            idleCommand = builtins.head (pkgs.lib.toList
              (builtins.head configs).home-manager.users.dokkan.systemd.user.services.noctalia-idle.Service.ExecStart);
          in
          assert pkgs.lib.all valid configs;
          assert (builtins.head configs).home-manager.users.dokkan.programs.noctalia.settings
            == (builtins.elemAt configs 1).home-manager.users.dokkan.programs.noctalia.settings;
          pkgs.runCommand "noctalia-integration-checked" { } ''
            # Costruisce anche il wrapper idle (incluso ShellCheck), senza avviarlo.
            test -x ${pkgs.lib.escapeShellArg idleCommand}
            touch "$out"
          '';
        noctalia-filesearch = pkgs.runCommand "noctalia-filesearch-checked" {
          nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils pkgs.gnugrep ];
        } ''
          python ${./tests/filesearch.py} ${./dotfiles/niri/scripts/filesearch.sh}
          touch "$out"
        '';
        lazyvim-nix = import ./tests/lazyvim-nix.nix { inherit pkgs; };
        # Il fiocco 3D di fastfetch: fotogrammi e player in un pty, con un
        # fastfetch finto. Più la config vera: il logo statico è lo stesso.
        fastfetch-spin = import ./tests/fastfetch-spin.nix { inherit pkgs; };
        fastfetch-config =
          let
            home = self.nixosConfigurations.armoredcoreVIP.config.home-manager.users.dokkan;
            spin = home.programs.fastfetch.package;
          in
          pkgs.runCommand "fastfetch-config-checked" { } ''
            # fastfetch vero: fallisce se @LOGO@ ha rotto il JSON.
            ${spin.unwrapped}/bin/fastfetch --pipe false --structure Break \
              --config ${home.xdg.configFile."fastfetch/config.jsonc".source} > raw
            strip() { sed -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' -e 's/[[:space:]]*$//' "$1"; }
            strip ${spin.logo.source} | grep -v '^$' > logo
            strip raw > shown
            # tutte le righe del fiocco statico compaiono nell'output
            test "$(grep -cFf logo shown)" -ge "$(wc -l < logo)"
            touch "$out"
          '';
        nixup = import ./tests/nixup.nix { inherit pkgs; };
        # Costruisce il wrapper vero: writeShellApplication esegue ShellCheck.
        # Il comando non viene avviato, quindi nessun update/switch nei test.
        nixup-package = import ./home/nixup.nix {
          inherit pkgs;
          repoPath = "/home/dokkan/nixos-config";
          hostName = "armoredcoreVIP";
        };
        nix-index-integration =
          let
            homes = map (host: self.nixosConfigurations.${host}.config.home-manager.users.dokkan)
              [ "armoredcoreVIP" "armoredcoreVIF" ];
            expected = nix-index-database.packages.${system}.nix-index-with-db;
          in
          assert pkgs.lib.all (home:
            home.programs.nix-index.enable
            && home.programs.nix-index.enableZshIntegration
            && !home.programs.nix-index-database.comma.enable
            && home.programs.nix-index.package.outPath == expected.outPath
          ) homes;
          # L'integrazione viene verificata senza scaricare l'intero DB
          # a ogni test; il download avviene nel rebuild della home.
          pkgs.runCommand "nix-index-integration-checked" { } ''
            touch "$out"
          '';

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
          assert home.programs.noctalia.settings.shell.font_family == "Monaspace Argon";
          assert !home.programs.noctalia.settings.theme.templates.enable_builtin_templates;
          assert !home.programs.noctalia.settings.theme.templates.enable_community_templates;
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
