{ config, osConfig, pkgs, ... }:

{
  home.packages = [
    (import ./nixup.nix {
      inherit pkgs;
      repoPath = "${config.home.homeDirectory}/nixos-config";
      hostName = osConfig.networking.hostName;
    })
  ];
}
