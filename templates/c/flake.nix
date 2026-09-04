{
  description = "Progetto C — toolchain e librerie nella devshell, non a sistema";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # `nix develop`, o automatico con direnv (`use flake` nell'.envrc)
      # I pacchetti sono in shell.nix: edita quello.
      devShells.${system}.default = import ./shell.nix { inherit pkgs; };
    };
}
