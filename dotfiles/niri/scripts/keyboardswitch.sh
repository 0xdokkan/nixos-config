#!/usr/bin/env sh
#
# keyboardswitch.sh — versione niri
#
# Originale HyDE: hyprctl switchxkblayout all next + parse del nome layout
# Niri: niri msg action switch-layout next + parse via niri msg --json keyboard-layouts

niri msg action switch-layout next

# Recupera il nome del layout attivo
lay_main=$(niri msg --json keyboard-layouts 2>/dev/null \
    | jq -r '.names[.current_idx]')

# Fallback se jq non riesce
[ -z "${lay_main}" ] && lay_main="(layout)"

notify-send -a "t1" -r 91190 -t 800 \
    -i "${HOME}/.config/dunst/icons/keyboard.svg" \
    "${lay_main}"
