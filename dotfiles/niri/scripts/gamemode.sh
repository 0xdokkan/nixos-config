#!/usr/bin/env sh
#
# gamemode.sh — versione NixOS
#
# Su NixOS ~/.config/niri/config.kdl è un symlink read-only nello store:
# la vecchia strategia (copiare config-gaming.kdl sopra config.kdl) non
# può funzionare. niri però sa caricare un config alternativo a runtime:
#     niri msg action load-config-file --path FILE
#
# config-gaming.kdl fa `include "config.kdl"` e sovrascrive SOLO gap e
# animazioni: viene validato a build-time da home/desktop.nix insieme
# alla config normale, quindi non può più andare fuori sync.

NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
NORMAL="${NIRI_DIR}/config.kdl"
GAMING="${NIRI_DIR}/config-gaming.kdl"
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/niri-gamemode.state"

current=$(cat "${STATE}" 2>/dev/null || echo "normal")

if [ "${current}" = "normal" ]; then
    niri msg action load-config-file --path "${GAMING}" || {
        notify-send -a niri "Game mode" "load-config-file fallito (vedi journal)"
        exit 1
    }
    echo "gaming" > "${STATE}"
    notify-send -a niri "Game mode" "ON — animazioni e gap disattivati"
else
    niri msg action load-config-file --path "${NORMAL}" || {
        notify-send -a niri "Game mode" "load-config-file fallito (vedi journal)"
        exit 1
    }
    echo "normal" > "${STATE}"
    notify-send -a niri "Game mode" "OFF — config normale ripristinata"
fi
