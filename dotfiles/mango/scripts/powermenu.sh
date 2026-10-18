#!/usr/bin/env bash
# Mod+Backspace, e il pulsante spegnimento nella barra e nel centro di
# controllo: un menu rofi per bloccare, uscire o spegnere.
# Sospendere blocca prima lo schermo (before-sleep di swayidle, idle.py).
set -euo pipefail

entries=(
    '󰌾  Blocca'
    '󰍃  Esci da mango'
    '󰤄  Sospendi'
    '󰜉  Riavvia'
    '󰐥  Spegni'
)

# -format i: rofi risponde con il numero della riga, non con il testo.
choice=$(printf '%s\n' "${entries[@]}" |
    rofi -dmenu -i -no-custom -format i -p sessione \
        -theme-str 'listview { lines: 5; }') || exit 0

case $choice in
    0) loginctl lock-session ;;
    1) mmsg dispatch quit > /dev/null ;;
    2) systemctl suspend ;;
    3) systemctl reboot ;;
    4) systemctl poweroff ;;
    *) exit 0 ;;
esac
