{
  description = "Sistema NixOS di Dokkan — il rice come sorgente";

  # ── Gli input: due soli, come da design. Resisti all'input creep! ──
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      # single source of truth: home-manager usa il NOSTRO nixpkgs
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # ── Il sistema: `sudo nixos-rebuild switch --flake .#portatilino` ──
      nixosConfigurations.portatilino = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./hosts/portatilino/configuration.nix

          # home-manager come modulo NixOS: sistema e home si buildano
          # e switchano INSIEME, atomicamente, in un solo comando
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.dokkan = import ./home;
            # se un rebuild trova dotfiles pre-esistenti non gestiti,
            # invece di fallire li salva con questo suffisso:
            home-manager.backupFileExtension = "hm-backup";
          }
        ];
      };

      # ── Arsenale CTF: `nix develop ~/nixos-config#ctf` da ovunque 🚩 ──
      devShells.${system}.ctf = pkgs.mkShell {
        packages = with pkgs; [
          gdb
          gef
          (python3.withPackages (ps: with ps; [
            pwntools
            pycryptodome
            ipython
          ]))
          # TODO: radare2? binwalk? ghidra? aggiungi il tuo kit
        ];
      };

      # TODO (dopo, con calma): devShells per i tuoi progetti C, l'engine...
      # oppure — meglio — un flake.nix DENTRO ogni repo di progetto.
    };
}
