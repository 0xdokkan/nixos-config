{ pkgs, repoPath, hostName }:

pkgs.writeShellApplication {
  name = "nixup";
  runtimeInputs = with pkgs; [ coreutils git jq nix nixos-rebuild nvd util-linux ];
  text = ''
    readonly NIXUP_REPO=${pkgs.lib.escapeShellArg repoPath}
    readonly NIXUP_HOST=${pkgs.lib.escapeShellArg hostName}
    readonly NIXUP_SYSTEM=/run/current-system
    readonly NIXUP_REBUILD=${pkgs.nixos-rebuild}/bin/nixos-rebuild
    ${builtins.readFile ./nixup.sh}
  '';
}
