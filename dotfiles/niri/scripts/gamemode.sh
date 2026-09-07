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

set -eu

# XDG_RUNTIME_DIR può sopravvivere a logout/login se restano altre sessioni
# dello stesso utente. NIRI_SOCKET identifica invece questa istanza di niri:
# una nuova istanza riparte in modalità normale, ignorando la vecchia cache.
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ -z "${NIRI_SOCKET:-}" ]; then
    printf '%s\n' 'gamemode: servono XDG_RUNTIME_DIR e NIRI_SOCKET della sessione niri' >&2
    exit 1
fi
if [ ! -d "${XDG_RUNTIME_DIR}" ] || [ ! -w "${XDG_RUNTIME_DIR}" ]; then
    printf '%s\n' 'gamemode: XDG_RUNTIME_DIR non è una directory scrivibile' >&2
    exit 1
fi

NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
NORMAL="${NIRI_DIR}/config.kdl"
GAMING="${NIRI_DIR}/config-gaming.kdl"
SESSION_ID=$(printf '%s' "${NIRI_SOCKET}" | sha256sum | cut -d ' ' -f 1)
STATE_DIR="${XDG_RUNTIME_DIR}/niri-gamemode"
STATE="${STATE_DIR}/${SESSION_ID}.state"

# Due pressioni ravvicinate devono fare ON e poi OFF, non leggere entrambe
# lo stesso stato. Il lock viene rilasciato automaticamente all'uscita.
umask 077
mkdir -p "${STATE_DIR}"
exec 9> "${STATE}.lock"
flock -x 9

current=normal
if [ -f "${STATE}" ]; then
    current=$(cat "${STATE}")
fi

case "${current}" in
    normal)
        next=gaming
        target="${GAMING}"
        message='ON — animazioni e gap disattivati'
        ;;
    gaming)
        next=normal
        target="${NORMAL}"
        message='OFF — config normale ripristinata'
        ;;
    *)
        printf '%s\n' "gamemode: stato non valido in ${STATE}" >&2
        exit 1
        ;;
esac

niri msg action load-config-file --path "${target}" || {
    printf '%s\n' 'gamemode: load-config-file fallito; stato precedente conservato' >&2
    notify-send -a niri "Game mode" "load-config-file fallito (vedi journal)" || true
    exit 1
}

printf '%s\n' "${next}" > "${STATE}"
# Un errore del demone notifiche non annulla un cambio già riuscito.
notify-send -a niri "Game mode" "${message}" || true
