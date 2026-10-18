#!/usr/bin/env bash
# Luce notturna con wl-gammarelay-rs (servizio utente, home/session.nix).
#   on / off  4000 K / 6500 K (come Alt+F8 / Alt+F9)
#   toggle    il pulsante luna nel centro di controllo: swaync passa lo
#             stato nuovo in SWAYNC_TOGGLE_STATE; da terminale inverte
#   status    "true" se è accesa: swaync lo legge per lo stato del pulsante
set -euo pipefail

NIGHT=4000
DAY=6500

temperature() {
    # Output di busctl: "q 6500"
    busctl --user get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature |
        awk '{ print $2 }'
}

set_temperature() {
    busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q "$1"
}

case ${1:-} in
    on) set_temperature "$NIGHT" ;;
    off) set_temperature "$DAY" ;;
    toggle)
        case ${SWAYNC_TOGGLE_STATE:-} in
            true) set_temperature "$NIGHT" ;;
            false) set_temperature "$DAY" ;;
            *)
                if (( $(temperature) < DAY )); then
                    set_temperature "$DAY"
                else
                    set_temperature "$NIGHT"
                fi
                ;;
        esac
        ;;
    status)
        # Senza wl-gammarelay (servizio fermo) la luce è spenta.
        current=$(temperature 2> /dev/null) || current=$DAY
        if (( ${current:-$DAY} < DAY )); then echo true; else echo false; fi
        ;;
    *)
        printf 'uso: %s on|off|toggle|status\n' "${0##*/}" >&2
        exit 2
        ;;
esac
