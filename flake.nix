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
  };

  outputs = { self, nixpkgs, home-manager, nix-index-database, helium-flake, llm-agents, ... }:
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
            home-manager.extraSpecialArgs = {
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

      # ── `nix flake check`: config mango, regressioni e impostazioni desktop ──
      # mango-config è la stessa derivazione linkata da home/mango.nix.
      checks.${system} = {
        mango-config = import ./home/mango-configs.nix { inherit pkgs; };
        mango-regressions =
          let
            # le cartelle VERE che home-manager linka su ciascun host
            mangoDir = host:
              self.nixosConfigurations.${host}.config.home-manager.users.dokkan.xdg.configFile."mango".source;
          in
          pkgs.runCommand "mango-regressions-checked" {
            nativeBuildInputs = [ pkgs.python3 ];
          } ''
            python ${./tests/mango-regressions.py} \
              --laptop ${mangoDir "armoredcoreVIP"} \
              --desktop ${mangoDir "armoredcoreVIF"}
            touch "$out"
          '';
        # La sessione: SDDM lancia il wrapper, il target esiste, keyring e
        # PAM di hyprlock ci sono, niente niri né hypridle.
        mango-session =
          let
            configs = map (host: self.nixosConfigurations.${host}.config)
              [ "armoredcoreVIP" "armoredcoreVIF" ];
            valid = c: let home = c.home-manager.users.dokkan; in
              c.programs.mango.enable
              && !c.programs.niri.enable
              && !c.services.hypridle.enable
              && c.services.gnome.gnome-keyring.enable
              && c.security.pam.services ? hyprlock
              && pkgs.lib.elem "mango" c.services.displayManager.sessionData.sessionNames
              && home.systemd.user.targets ? mango-session
              && pkgs.lib.elem "graphical-session.target"
                home.systemd.user.targets.mango-session.Unit.BindsTo;
            mango = (builtins.head configs).programs.mango.package;
            vif = (builtins.elemAt configs 1).environment.etc;
            nvidiaProfile = vif."nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json".text;
          in
          assert pkgs.lib.all valid configs;
          assert (builtins.head (builtins.fromJSON nvidiaProfile).rules).pattern.matches == "mango";
          pkgs.runCommand "mango-session-checked" { } ''
            desktop=${mango}/share/wayland-sessions/mango.desktop
            grep -qx 'Exec=/nix/store/.*/bin/mango-session' "$desktop"
            exec=$(sed -n 's/^Exec=//p' "$desktop")
            test -x "$exec"
            grep -q '/bin/mango "$@"' "$exec"
            test -x ${mango}/bin/mango && test -x ${mango}/bin/mmsg
            touch "$out"
          '';
        # Gli script dei bind: ShellCheck, comandi finti, nessuno mancante.
        # gamemode e filesearch hanno i loro test, più vecchi e più fitti.
        mango-scripts = import ./tests/mango-scripts.nix {
          inherit pkgs;
          scripts = import ./home/mango-scripts.nix { inherit pkgs; };
          home = self.nixosConfigurations.armoredcoreVIP.config.home-manager.users.dokkan;
        };
        mango-gamemode = import ./tests/gamemode.nix { inherit pkgs; };
        # idle.py con bus, locker e power manager simulati, più il controllo
        # sulla riga con cui hyprlock conferma il lock.
        idle = import ./tests/idle.nix { inherit pkgs; };
        # I pezzi del desktop ci sono, su entrambi gli host, e partono con
        # la sessione grafica.
        desktop-integration =
          let
            configs = map (host: self.nixosConfigurations.${host}.config)
              [ "armoredcoreVIP" "armoredcoreVIF" ];
            homeOf = c: c.home-manager.users.dokkan;
            laptop = c: c.networking.hostName == "armoredcoreVIP";
            boundToSession = unit:
              pkgs.lib.elem "graphical-session.target" unit.Install.WantedBy
              && pkgs.lib.elem "graphical-session.target" unit.Unit.PartOf;
            valid = c: let home = homeOf c; in
              c.services.upower.enable
              && c.security.polkit.enable
              && c.services.power-profiles-daemon.enable
              && home.programs.waybar.enable
              && home.programs.waybar.systemd.enable
              && home.programs.rofi.enable
              && home.services.swaync.enable
              && home.services.swayosd.enable
              && home.services.polkit-gnome.enable
              && home.services.cliphist.enable
              && home.services.wl-clip-persist.enable
              && home.services.awww.enable
              && home.services.udiskie.enable
              && !home.services.udiskie.automount
              && home.programs.hyprlock.enable
              && home.services.batsignal.enable == laptop c
              && boundToSession home.systemd.user.services.idle
              && boundToSession home.systemd.user.services.wl-gammarelay-rs
              && boundToSession home.systemd.user.services.wallpaper
              && pkgs.lib.elem "wallpaper.sh" (map (p: p.meta.mainProgram or "") home.home.packages)
              && home.systemd.user.services.hyprlock.Unit.X-RestartIfChanged == false
              && !(home.systemd.user.services.hyprlock ? Install)
              && home.xdg.desktopEntries ? wifi-qr
              && pkgs.lib.elem "battery" home.programs.waybar.settings.main.modules-right == laptop c
              && !(home.xdg.configFile ? "noctalia/config.toml");
            home = homeOf (builtins.head configs);
            idleCommand = home.systemd.user.services.idle.Service.ExecStart;
            lockCommand = home.systemd.user.services.hyprlock.Service.ExecStart;
            rofiConfig = home.home.file."${home.home.homeDirectory}/.config/rofi/config.rasi".source;
            python = pkgs.python3.withPackages (ps: [ ps.jsonschema ]);
          in
          assert pkgs.lib.all valid configs;
          pkgs.runCommand "desktop-integration-checked" {
            nativeBuildInputs = [ pkgs.jq python home.programs.rofi.finalPackage home.programs.hyprlock.package ];
          } ''
            export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR XDG_CACHE_HOME=$TMPDIR
            # Costruisce i wrapper (incluso ShellCheck), senza avviarli.
            test -x ${pkgs.lib.escapeShellArg idleCommand}
            grep -q 'hyprlock.log' ${pkgs.lib.escapeShellArg lockCommand}
            jq -e '.[0]["modules-left"] == ["ext/workspaces"]' \
              ${home.xdg.configFile."waybar/config".source}
            grep -qx 'show_pass = wifi-qr' \
              ${home.xdg.configFile."networkmanager-dmenu/config.ini".source}

            # rofi con un tema rotto torna in silenzio a quello di default:
            # il tema letto deve essere il nostro.
            rofi -config ${rofiConfig} -dump-theme > theme
            grep -q 'accent: *rgba ( 122, 162, 247' theme
            grep -q 'width: *440px' theme

            # swaync: la config rispetta lo schema della versione installata.
            python - ${home.xdg.configFile."swaync/config.json".source} \
              ${home.services.swaync.package}/etc/xdg/swaync/configSchema.json <<'PY'
            import json, sys, jsonschema
            config, schema = (json.load(open(path)) for path in sys.argv[1:])
            jsonschema.validators.validator_for(schema)(schema).validate(config)
            PY

            # hyprlock legge la config prima di cercare il display: gli
            # errori (opzioni inesistenti) arrivano anche senza Wayland.
            hyprlock -c ${home.xdg.configFile."hypr/hyprlock.conf".source} > hyprlock.log 2>&1 || true
            cat hyprlock.log
            grep -q "Couldn't connect to a wayland compositor" hyprlock.log
            if grep -qi 'config error' hyprlock.log; then exit 1; fi
            touch "$out"
          '';
        filesearch = pkgs.runCommand "filesearch-checked" {
          nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils pkgs.gnugrep ];
        } ''
          python ${./tests/filesearch.py} ${./dotfiles/mango/scripts/filesearch.sh}
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

      # ── Anteprima del desktop in una VM: `nix build .#desktop-preview` ──
      # mango vero con le config del portatile; screenshot in result/.
      # Non è un check: ci mette minuti e nixup lancia i check a ogni update.
      packages.${system}.desktop-preview = import ./tests/desktop-preview.nix {
        inherit pkgs;
        home = self.nixosConfigurations.armoredcoreVIP.config.home-manager.users.dokkan;
        wallpaper = ./dotfiles/sddm/bg.png;
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
