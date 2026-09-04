#!/usr/bin/env sh
#
# windowpin.sh — versione niri (workaround: niri non ha "pin")
#
# Hyprland: dispatch pin (la finestra resta visibile su tutti i workspace)
# niri:     non c'è equivalente diretto. Il sostituto più vicino è
#           toggle-window-floating + center-window: la finestra diventa
#           floating al centro del workspace corrente. Se vuoi che
#           riappaia su altri workspace, devi spostartela manualmente.
#
# In alternativa, considera:
#  - lasciare la finestra in un workspace dedicato e usare focus-workspace
#  - usare overview (Mod+S) per tenere d'occhio la finestra in pip/nota
#
# Questo script approssima il comportamento toggle pin facendo
# float+center, e se è già floating la rimette tile.

is_floating=$(niri msg --json focused-window 2>/dev/null | jq -r '.is_floating')

if [ "${is_floating}" = "true" ]; then
    # già floating → ritorna tile
    niri msg action toggle-window-floating
else
    # tile → diventa floating e centrala
    niri msg action toggle-window-floating
    niri msg action center-window
fi
