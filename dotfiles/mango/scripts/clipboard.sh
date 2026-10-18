#!/usr/bin/env bash
# Mod+V e il riquadro appunti nella barra: la cronologia di cliphist in
# rofi. Invio copia la voce (poi Ctrl+V per incollarla); Shift+Canc la
# cancella dalla cronologia e riapre il menu; Esc chiude.
set -euo pipefail

while true; do
    status=0
    # cliphist list: "id<TAB>anteprima"; rofi mostra solo l'anteprima.
    # Shift+Canc in rofi cancella le voci della cronologia di drun: qui
    # serve libero per il tasto personalizzato (esce con 10).
    selection=$(cliphist list |
        rofi -dmenu -i -no-custom -p appunti -display-columns 2 \
            -kb-delete-entry '' -kb-custom-1 'Shift+Delete' \
            -mesg 'Invio copia · Shift+Canc cancella') || status=$?
    case $status in
        0)
            cliphist decode <<< "$selection" | wl-copy
            exit 0
            ;;
        10) cliphist delete <<< "$selection" ;;
        *) exit 0 ;;
    esac
done
