{ pkgs, repoPath, hostName }:

let
  # Il pin di Codex alpha (home/codex-alpha.json) non è un input del
  # flake: dopo `nix flake update` lo aggiorna questo script.
  codexAlphaUpdate = pkgs.writeShellApplication {
    name = "codex-alpha-update";
    runtimeInputs = with pkgs; [ coreutils curl jq nix ];
    text = builtins.readFile ./codex-alpha-update.sh;
  };
in
pkgs.writeShellApplication {
  name = "nixup";
  runtimeInputs = with pkgs; [ coreutils git jq nix nixos-rebuild nvd util-linux ];
  text = ''
    readonly NIXUP_REPO=${pkgs.lib.escapeShellArg repoPath}
    readonly NIXUP_HOST=${pkgs.lib.escapeShellArg hostName}
    readonly NIXUP_SYSTEM=/run/current-system
    readonly NIXUP_REBUILD=${pkgs.nixos-rebuild}/bin/nixos-rebuild
    readonly NIXUP_PIN_UPDATE=${codexAlphaUpdate}/bin/codex-alpha-update
    ${builtins.readFile ./nixup.sh}
  '';
}
