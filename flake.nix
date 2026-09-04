{
  description = "Sistema NixOS di Dokkan — il rice come sorgente";

  # ── Gli input: pochi e giustificati. Resisti all'input creep! ──
  #   nixpkgs + home-manager: la base.
  #   helium-flake: Helium non è in nixpkgs (upstream pubblica solo .deb),
  #                 questo flake lo estrae e lo patcha. Voluto. :3
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
  };

  outputs = { self, nixpkgs, home-manager, helium-flake, ... }:
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
        portatilino = mkHost "portatilino";   # ThinkPad T470s, Intel
        fisso       = mkHost "fisso";         # desktop, RTX 2070 nvidia
      };

      # ── `nix flake check` COSTRUISCE questi: niri validate sui due config.kdl ──
      # (è la stessa derivazione che home/desktop.nix linka in ~/.config/niri)
      checks.${system}.niri-config = import ./home/niri-configs.nix { inherit pkgs; };

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
