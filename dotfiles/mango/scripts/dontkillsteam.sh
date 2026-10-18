#!/usr/bin/env bash
# Mod+Q / Alt+F4: chiude la finestra a fuoco. Se è Steam la nasconde
# soltanto (unmap della finestra X11): Steam resta aperto nel tray e
# rilanciarlo da rofi la rimostra. Se xdotool non ci riesce, la chiude
# normalmente come tutte le altre.
set -euo pipefail

app=$(mmsg get focusing-client | jq -r '.appid // empty')

if [[ ${app,,} == steam ]] && xdotool getactivewindow windowunmap; then
    exit 0
fi
mmsg dispatch killclient > /dev/null
