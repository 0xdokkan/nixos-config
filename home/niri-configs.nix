# ══ niri: config.kdl + config-gaming.kdl, intonsi, validati a BUILD-TIME ══
# Se una delle due è invalida il sistema si rifiuta di buildare. ✨
#
# È una funzione { pkgs } → derivazione perché la usano in due:
#   - home/desktop.nix  → la linka in ~/.config/niri/
#   - flake.nix         → la espone in `checks`, così `nix flake check`
#                         fa girare `niri validate` davvero (senza dover
#                         buildare tutto il sistema per scoprire un typo)
# Stessi input → stesso hash → la derivazione è una sola.
#
# Le due config stanno nella stessa directory dello store perché
# config-gaming.kdl fa `include "config.kdl"` (path relativo).
{ pkgs }:

pkgs.runCommand "niri-config-checked"
  { nativeBuildInputs = [ pkgs.niri ]; } ''
  mkdir -p $out
  cp ${../dotfiles/niri/config.kdl}        $out/config.kdl
  cp ${../dotfiles/niri/config-gaming.kdl} $out/config-gaming.kdl
  niri validate --config $out/config.kdl
  niri validate --config $out/config-gaming.kdl
''
