# ══ niri: config.kdl + config-gaming.kdl + host.kdl, validati a BUILD-TIME ══
# Se una delle config è invalida il sistema si rifiuta di buildare. ✨
#
# È una funzione { pkgs, layout } → derivazione perché la usano in due:
#   - home/desktop.nix  → la linka in ~/.config/niri/ (col layout dell'host)
#   - flake.nix         → la espone in `checks`, così `nix flake check`
#                         fa girare `niri validate` davvero (senza dover
#                         buildare tutto il sistema per scoprire un typo)
#
# Le config stanno nella stessa directory dello store perché si includono
# a vicenda con path relativi:
#   config-gaming.kdl → include "config.kdl" → include "host.kdl"
#
# host.kdl è l'UNICO pezzo di niri che cambia tra fisso e portatilino:
# il layout della tastiera (US sul fisso, IT sul portatile). Lo generiamo
# qui dal valore che l'host dichiara in services.xserver.xkb.layout.
{ pkgs, layout ? "us" }:

pkgs.runCommand "niri-config-checked"
  { nativeBuildInputs = [ pkgs.niri ]; } ''
  mkdir -p $out
  cp ${../dotfiles/niri/config.kdl}        $out/config.kdl
  cp ${../dotfiles/niri/config-gaming.kdl} $out/config-gaming.kdl
  cat > $out/host.kdl <<EOF
  // GENERATO da home/niri-configs.nix — layout = services.xserver.xkb.layout dell'host
  input {
      keyboard {
          xkb {
              layout "${layout}"
          }
      }
  }
  EOF
  niri validate --config $out/config.kdl
  niri validate --config $out/config-gaming.kdl
''
